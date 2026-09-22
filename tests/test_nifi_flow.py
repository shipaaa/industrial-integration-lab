import argparse
import importlib.util
import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC_PATH = ROOT / "nifi" / "telemetry-flow.json"
BOOTSTRAP_PATH = ROOT / "scripts" / "bootstrap-nifi.py"


def load_bootstrap_module():
    module_spec = importlib.util.spec_from_file_location(
        "bootstrap_nifi", BOOTSTRAP_PATH
    )
    if module_spec is None or module_spec.loader is None:
        raise RuntimeError("Could not load bootstrap-nifi.py")
    module = importlib.util.module_from_spec(module_spec)
    module_spec.loader.exec_module(module)
    return module


class NifiFlowSpecificationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.spec = json.loads(SPEC_PATH.read_text(encoding="utf-8"))
        cls.processors = {item["key"]: item for item in cls.spec["processors"]}
        cls.connections = {
            tuple(connection) for connection in cls.spec["connections"]
        }

    def test_specification_and_component_keys_are_unique(self) -> None:
        self.assertEqual(self.spec["schema_version"], "1.0")
        self.assertEqual(self.spec["nifi_version"], "2.10.0")
        keys = [item["key"] for item in self.spec["processors"]]
        self.assertEqual(len(keys), len(set(keys)))

    def test_all_connections_reference_known_processors(self) -> None:
        relationships_by_type = {
            "GenerateFlowFile": {"success"},
            "ExecuteSQLRecord": {"success", "failure"},
            "EvaluateJsonPath": {"matched", "unmatched", "failure"},
            "UpdateAttribute": {"success"},
            "InvokeHTTP": {"original", "response", "retry", "no retry", "failure"},
            "RetryFlowFile": {"retry", "retries_exceeded", "failure"},
            "ExtractText": {"matched", "unmatched"},
            "ExecuteSQL": {"success", "failure"},
            "RouteOnAttribute": {"continue", "unmatched"},
            "LogAttribute": {"success"},
        }
        for source, relationship, destination in self.spec["connections"]:
            self.assertIn(source, self.processors)
            self.assertIn(destination, self.processors)
            processor_type = self.processors[source]["type"].rsplit(".", 1)[-1]
            self.assertIn(
                relationship.casefold(),
                relationships_by_type[processor_type],
                f"{source}: {relationship}",
            )

    def test_auto_terminated_relationship_names_use_nifi_case(self) -> None:
        relationships_by_type = {
            "GenerateFlowFile": {"success"},
            "ExecuteSQLRecord": {"success", "failure"},
            "EvaluateJsonPath": {"matched", "unmatched", "failure"},
            "UpdateAttribute": {"success"},
            "InvokeHTTP": {"Original", "Response", "Retry", "No Retry", "Failure"},
            "RetryFlowFile": {"retry", "retries_exceeded", "failure"},
            "ExtractText": {"matched", "unmatched"},
            "ExecuteSQL": {"success", "failure"},
            "RouteOnAttribute": {"continue", "unmatched"},
            "LogAttribute": {"success"},
        }
        for processor in self.spec["processors"]:
            processor_type = processor["type"].rsplit(".", 1)[-1]
            for relationship in processor.get("auto_terminate", []):
                self.assertIn(
                    relationship,
                    relationships_by_type[processor_type],
                    f"{processor['key']}: {relationship}",
                )

    def test_page_is_loaded_before_pagination_continues(self) -> None:
        self.assertIn(("load_page", "success", "route_more"), self.connections)
        self.assertIn(("route_more", "continue", "prepare_next"), self.connections)
        self.assertIn(("prepare_next", "success", "build_request"), self.connections)
        self.assertNotIn(("extract_page", "matched", "prepare_next"), self.connections)

    def test_api_and_database_failures_have_bounded_retries(self) -> None:
        self.assertIn(("invoke_api", "retry", "retry_api"), self.connections)
        self.assertIn(("invoke_api", "failure", "retry_api"), self.connections)
        self.assertIn(("retry_api", "retries_exceeded", "failure"), self.connections)
        self.assertIn(("load_page", "failure", "retry_db"), self.connections)
        self.assertIn(("retry_db", "retries_exceeded", "failure"), self.connections)

    def test_page_transaction_uses_parameterized_sql(self) -> None:
        properties = self.processors["load_page"]["properties"]
        self.assertEqual(
            properties["SQL Query"],
            "SELECT ods.load_telemetry_page(?::jsonb, ?::text, ?::text)",
        )
        preparation = self.processors["prepare_db"]["properties"]
        self.assertEqual(preparation["sql.args.1.value"], "${telemetry.page}")
        self.assertEqual(preparation["sql.args.1.type"], "12")

    def test_request_contains_both_watermark_parts(self) -> None:
        request_url = self.processors["build_request"]["properties"][
            "telemetry.request.url"
        ]
        self.assertIn("updated_since=", request_url)
        self.assertIn("after_record_id=", request_url)
        self.assertIn("urlEncode()", request_url)

    def test_sensitive_database_password_is_a_parameter(self) -> None:
        parameters = {
            item["name"]: item for item in self.spec["parameter_context"]["parameters"]
        }
        self.assertTrue(parameters["PostgreSQL Password"]["sensitive"])
        pool = self.spec["controller_services"][0]
        self.assertEqual(pool["properties"]["Password"], "#{PostgreSQL Password}")


class NifiBootstrapHelperTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.bootstrap = load_bootstrap_module()

    def test_bundle_aliases_are_resolved(self) -> None:
        bundle = self.bootstrap.bundle_for(
            {"bundle": "update-attribute"}, "2.10.0"
        )
        self.assertEqual(bundle["artifact"], "nifi-update-attribute-nar")
        self.assertEqual(bundle["version"], "2.10.0")

    def test_service_references_are_resolved(self) -> None:
        resolved = self.bootstrap.resolve_service_references(
            {"Pool": "@service:postgres_pool", "Other": "literal"},
            {"postgres_pool": {"id": "service-id"}},
        )
        self.assertEqual(resolved, {"Pool": "service-id", "Other": "literal"})

    def test_relationship_names_are_case_insensitive(self) -> None:
        processor = {
            "name": "Invoke Telemetry API",
            "relationships": [{"name": "No Retry"}],
        }
        self.assertEqual(
            self.bootstrap.relationship_name(processor, "no retry"), "No Retry"
        )

    def test_root_process_group_position_is_parsed(self) -> None:
        self.assertEqual(self.bootstrap.parse_position("600,0"), (600.0, 0.0))
        with self.assertRaises(argparse.ArgumentTypeError):
            self.bootstrap.parse_position("600")

    def test_parallel_connections_receive_distinct_bends(self) -> None:
        spec = {
            "processors": [
                {"key": "source", "position": [0, 0]},
                {"key": "destination", "position": [400, 0]},
            ],
            "connections": [
                ["source", "failure", "destination"],
                ["destination", "retry", "source"],
            ],
        }
        bends = self.bootstrap.connection_bends(spec)
        self.assertNotEqual(
            bends[("source", "failure", "destination")],
            bends[("destination", "retry", "source")],
        )

    def test_layout_sync_updates_only_changed_processor_positions(self) -> None:
        class RecordingClient:
            def __init__(self) -> None:
                self.requests = []

            def request(self, method, path, payload=None):
                self.requests.append((method, path, payload))

        client = RecordingClient()
        spec = {
            "processors": [
                {"name": "Already placed", "position": [0, 0]},
                {"name": "Move me", "position": [350, 175]},
            ]
        }
        entities = [
            {
                "id": "placed-id",
                "revision": {"version": 1},
                "component": {
                    "name": "Already placed",
                    "position": {"x": 0, "y": 0},
                },
            },
            {
                "id": "move-id",
                "revision": {"version": 7},
                "component": {
                    "name": "Move me",
                    "position": {"x": 10, "y": 20},
                },
            },
        ]

        self.bootstrap.synchronize_processor_positions(client, spec, entities)

        self.assertEqual(
            client.requests,
            [
                (
                    "PUT",
                    "/processors/move-id",
                    {
                        "revision": {"version": 7},
                        "component": {
                            "id": "move-id",
                            "position": {"x": 350, "y": 175},
                        },
                    },
                )
            ],
        )

    def test_error_sink_connections_use_separate_layout_rails(self) -> None:
        spec = {
            "processors": [
                {"key": "first", "position": [0, 0]},
                {"key": "second", "position": [300, 0]},
                {
                    "key": "failure",
                    "position": [900, 600],
                    "layout_role": "error_sink",
                },
            ],
            "connections": [
                ["first", "failure", "failure"],
                ["second", "failure", "failure"],
            ],
        }

        bends = self.bootstrap.connection_bends(spec)

        first = bends[("first", "failure", "failure")]
        second = bends[("second", "failure", "failure")]
        self.assertEqual(len(first), 2)
        self.assertEqual(len(second), 2)
        self.assertNotEqual(first[0]["y"], second[0]["y"])
        self.assertEqual(first[1]["x"], 800.0)
        self.assertEqual(second[1]["x"], 800.0)

    def test_explicit_connection_bends_override_automatic_layout(self) -> None:
        spec = {
            "processors": [
                {"key": "source", "position": [0, 0]},
                {"key": "destination", "position": [300, 0]},
            ],
            "connections": [["source", "success", "destination"]],
            "connection_bends": [
                {
                    "source": "source",
                    "relationship": "success",
                    "destination": "destination",
                    "points": [[100, 200], [250, 200]],
                }
            ],
        }

        bends = self.bootstrap.connection_bends(spec)

        self.assertEqual(
            bends[("source", "success", "destination")],
            [{"x": 100.0, "y": 200.0}, {"x": 250.0, "y": 200.0}],
        )

    def test_managed_flows_use_compact_non_overlapping_layouts(self) -> None:
        for spec_path in sorted((ROOT / "nifi").glob("*-flow.json")):
            spec = json.loads(spec_path.read_text(encoding="utf-8"))
            positions = [tuple(item["position"]) for item in spec["processors"]]
            xs = [position[0] for position in positions]
            ys = [position[1] for position in positions]

            with self.subTest(spec=spec_path.name):
                self.assertEqual(len(positions), len(set(positions)))
                self.assertLessEqual(max(xs) - min(xs), 3000)
                self.assertLessEqual(max(ys) - min(ys), 1800)


if __name__ == "__main__":
    unittest.main()
