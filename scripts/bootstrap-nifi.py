#!/usr/bin/env python3
"""Create a source-controlled process group through the NiFi REST API."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SPEC = ROOT / "nifi" / "telemetry-flow.json"


class NifiError(RuntimeError):
    pass


class NifiClient:
    def __init__(self, base_url: str, username: str, password: str) -> None:
        self.base_url = base_url.rstrip("/")
        self.username = username
        self.password = password
        self.token: str | None = None
        self.ssl_context = ssl.create_default_context()
        self.ssl_context.check_hostname = False
        self.ssl_context.verify_mode = ssl.CERT_NONE

    def request(
        self,
        method: str,
        path: str,
        payload: dict[str, Any] | None = None,
        form: dict[str, str] | None = None,
    ) -> Any:
        headers: dict[str, str] = {
            "Accept": "text/plain" if form is not None else "application/json"
        }
        data: bytes | None = None
        if payload is not None:
            data = json.dumps(payload).encode("utf-8")
            headers["Content-Type"] = "application/json"
        elif form is not None:
            data = urllib.parse.urlencode(form).encode("utf-8")
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        if self.token is not None:
            headers["Authorization"] = f"Bearer {self.token}"

        request = urllib.request.Request(
            f"{self.base_url}{path}", data=data, headers=headers, method=method
        )
        try:
            with urllib.request.urlopen(
                request, context=self.ssl_context, timeout=30
            ) as response:
                body = response.read().decode("utf-8")
        except urllib.error.HTTPError as error:
            detail = error.read().decode("utf-8", errors="replace")
            raise NifiError(
                f"NiFi {method} {path} returned HTTP {error.code}: {detail}"
            ) from error
        except urllib.error.URLError as error:
            raise NifiError(f"NiFi {method} {path} failed: {error.reason}") from error

        if not body:
            return None
        content_type = response.headers.get("Content-Type", "")
        if "json" in content_type:
            return json.loads(body)
        return body

    def authenticate(self) -> None:
        token = self.request(
            "POST",
            "/access/token",
            form={"username": self.username, "password": self.password},
        )
        if not isinstance(token, str) or not token:
            raise NifiError("NiFi returned an empty authentication token")
        self.token = token

    def wait_until_ready(self, timeout_seconds: int) -> None:
        deadline = time.monotonic() + timeout_seconds
        last_error = "NiFi has not answered yet"
        while time.monotonic() < deadline:
            try:
                self.authenticate()
                return
            except NifiError as error:
                last_error = str(error)
                time.sleep(5)
        raise NifiError(f"NiFi was not ready after {timeout_seconds}s: {last_error}")


def revision(entity: dict[str, Any]) -> dict[str, Any]:
    current = entity.get("revision", {})
    result: dict[str, Any] = {"version": current.get("version", 0)}
    if current.get("clientId"):
        result["clientId"] = current["clientId"]
    return result


def spec_digest(spec_path: Path) -> str:
    return hashlib.sha256(spec_path.read_bytes()).hexdigest()


def parse_position(value: str) -> tuple[float, float]:
    try:
        x_text, y_text = value.split(",", 1)
        return float(x_text), float(y_text)
    except ValueError as error:
        raise argparse.ArgumentTypeError(
            "position must use the X,Y format, for example 600,0"
        ) from error


def load_spec(spec_path: Path) -> dict[str, Any]:
    with spec_path.open(encoding="utf-8") as source:
        spec = json.load(source)
    if spec.get("schema_version") != "1.0":
        raise NifiError("Unsupported NiFi flow specification schema_version")
    return spec


def find_parameter_context(
    client: NifiClient, name: str
) -> dict[str, Any] | None:
    response = client.request("GET", "/flow/parameter-contexts")
    for entity in response.get("parameterContexts", []):
        if entity.get("component", {}).get("name") == name:
            return entity
    return None


def create_parameter_context(
    client: NifiClient, context_spec: dict[str, Any]
) -> dict[str, Any]:
    existing = find_parameter_context(client, context_spec["name"])
    if existing is not None:
        return existing

    parameters = [
        {
            "parameter": {
                "name": item["name"],
                "description": item.get("description", "Managed from Git"),
                "sensitive": item.get("sensitive", False),
                "value": item["value"],
            }
        }
        for item in context_spec["parameters"]
    ]
    return client.request(
        "POST",
        "/parameter-contexts",
        payload={
            "revision": {"version": 0},
            "component": {
                "name": context_spec["name"],
                "description": context_spec.get("description", ""),
                "parameters": parameters,
            },
        },
    )


def root_process_groups(client: NifiClient) -> list[dict[str, Any]]:
    response = client.request("GET", "/flow/process-groups/root")
    return response["processGroupFlow"]["flow"].get("processGroups", [])


def find_process_group(client: NifiClient, name: str) -> dict[str, Any] | None:
    for entity in root_process_groups(client):
        if entity.get("component", {}).get("name") == name:
            return entity
    return None


def create_process_group(
    client: NifiClient,
    flow_spec: dict[str, Any],
    context_id: str,
    digest: str,
    position: tuple[float, float],
) -> dict[str, Any]:
    flow = flow_spec["flow"]
    comments = f"{flow['comments']} Spec SHA-256: {digest}"
    existing = find_process_group(client, flow["name"])
    if existing is not None:
        existing_comments = existing.get("component", {}).get("comments", "")
        if digest not in existing_comments:
            raise NifiError(
                f"The existing {flow['name']} process group was created from another "
                "specification. Reset the NiFi volumes before provisioning this version."
            )
        return existing

    return client.request(
        "POST",
        "/process-groups/root/process-groups",
        payload={
            "revision": {"version": 0},
            "component": {
                "name": flow["name"],
                "comments": comments,
                "position": {"x": position[0], "y": position[1]},
                "parameterContext": {"id": context_id},
            },
        },
    )


def set_process_group_position(
    client: NifiClient,
    group: dict[str, Any],
    position: tuple[float, float],
) -> dict[str, Any]:
    component = group["component"]
    current = component.get("position", {})
    if current.get("x") == position[0] and current.get("y") == position[1]:
        return group
    group_id = group.get("id") or component["id"]
    return client.request(
        "PUT",
        f"/process-groups/{group_id}",
        payload={
            "revision": revision(group),
            "component": {
                "id": group_id,
                "position": {"x": position[0], "y": position[1]},
            },
        },
    )


def bundle_for(item: dict[str, Any], nifi_version: str) -> dict[str, str]:
    bundle = item.get("bundle", "standard")
    if isinstance(bundle, dict):
        return bundle
    artifacts = {
        "standard": "nifi-standard-nar",
        "update-attribute": "nifi-update-attribute-nar",
    }
    try:
        artifact = artifacts[bundle]
    except KeyError as error:
        raise NifiError(f"Unknown bundle alias: {bundle}") from error
    return {
        "group": "org.apache.nifi",
        "artifact": artifact,
        "version": nifi_version,
    }


def resolve_service_references(
    properties: dict[str, str], services: dict[str, dict[str, Any]]
) -> dict[str, str]:
    resolved: dict[str, str] = {}
    for name, value in properties.items():
        if isinstance(value, str) and value.startswith("@service:"):
            key = value.removeprefix("@service:")
            if key not in services:
                raise NifiError(f"Unknown controller service reference: {key}")
            value = services[key]["id"]
        resolved[name] = value
    return resolved


def create_controller_services(
    client: NifiClient, group_id: str, spec: dict[str, Any]
) -> dict[str, dict[str, Any]]:
    created: dict[str, dict[str, Any]] = {}
    for item in spec["controller_services"]:
        entity = client.request(
            "POST",
            f"/process-groups/{group_id}/controller-services",
            payload={
                "revision": {"version": 0},
                "component": {
                    "name": item["name"],
                    "type": item["type"],
                    "bundle": item["bundle"],
                    "properties": item.get("properties", {}),
                },
            },
        )
        created[item["key"]] = entity["component"]
        client.request(
            "PUT",
            f"/controller-services/{entity['id']}/run-status",
            payload={"revision": revision(entity), "state": "ENABLED"},
        )
    return created


def wait_for_services(
    client: NifiClient, services: dict[str, dict[str, Any]], timeout: int = 60
) -> None:
    deadline = time.monotonic() + timeout
    pending = {service["id"] for service in services.values()}
    while pending and time.monotonic() < deadline:
        for service_id in list(pending):
            entity = client.request("GET", f"/controller-services/{service_id}")
            component = entity.get("component", {})
            if component.get("validationStatus") == "INVALID":
                errors = "; ".join(component.get("validationErrors", []))
                raise NifiError(
                    f"Controller service {component.get('name', service_id)} "
                    f"is invalid: {errors}"
                )
            if component.get("state") == "ENABLED":
                pending.remove(service_id)
        if pending:
            time.sleep(2)
    if pending:
        raise NifiError(f"Controller services did not enable: {sorted(pending)}")


def create_processors(
    client: NifiClient,
    group_id: str,
    spec: dict[str, Any],
    services: dict[str, dict[str, Any]],
) -> dict[str, dict[str, Any]]:
    created: dict[str, dict[str, Any]] = {}
    for item in spec["processors"]:
        x, y = item["position"]
        entity = client.request(
            "POST",
            f"/process-groups/{group_id}/processors",
            payload={
                "revision": {"version": 0},
                "component": {
                    "name": item["name"],
                    "type": item["type"],
                    "bundle": bundle_for(item, spec["nifi_version"]),
                    "position": {"x": x, "y": y},
                    "config": {
                        "properties": resolve_service_references(
                            item.get("properties", {}), services
                        ),
                        "schedulingStrategy": item.get(
                            "scheduling_strategy", "TIMER_DRIVEN"
                        ),
                        "schedulingPeriod": item.get("scheduling_period", "0 sec"),
                        "concurrentlySchedulableTaskCount": 1,
                        "executionNode": "ALL",
                        "penaltyDuration": "30 sec",
                        "yieldDuration": "1 sec",
                        "bulletinLevel": "WARN",
                        "autoTerminatedRelationships": item.get(
                            "auto_terminate", []
                        ),
                    },
                },
            },
        )
        created[item["key"]] = entity["component"]
    return created


def relationship_name(processor: dict[str, Any], requested: str) -> str:
    for relationship in processor.get("relationships", []):
        actual = relationship["name"]
        if actual.casefold() == requested.casefold():
            return actual
    available = [item["name"] for item in processor.get("relationships", [])]
    raise NifiError(
        f"Processor {processor['name']} has no relationship {requested!r}; "
        f"available: {available}"
    )


def connection_bends(spec: dict[str, Any]) -> dict[tuple[str, str, str], list[dict[str, float]]]:
    positions = {
        item["key"]: (float(item["position"][0]), float(item["position"][1]))
        for item in spec["processors"]
    }
    connections_by_endpoints: dict[
        tuple[str, str], list[tuple[str, str, str]]
    ] = {}
    for source_key, relationship, destination_key in spec["connections"]:
        connection = (source_key, relationship, destination_key)
        connections_by_endpoints.setdefault(
            tuple(sorted((source_key, destination_key))), []
        ).append(connection)

    bends: dict[tuple[str, str, str], list[dict[str, float]]] = {}
    for connections in connections_by_endpoints.values():
        if len(connections) < 2:
            continue
        source_key, _, destination_key = connections[0]
        source_x, source_y = positions[source_key]
        destination_x, destination_y = positions[destination_key]
        midpoint_x = (source_x + destination_x) / 2
        midpoint_y = (source_y + destination_y) / 2
        for index, connection in enumerate(connections):
            direction = 1 if index % 2 == 0 else -1
            distance = 120.0 * (index // 2 + 1)
            bends[connection] = [
                {"x": midpoint_x, "y": midpoint_y + direction * distance}
            ]
    return bends


def create_connections(
    client: NifiClient,
    group_id: str,
    spec: dict[str, Any],
    processors: dict[str, dict[str, Any]],
) -> None:
    bends_by_connection = connection_bends(spec)
    for source_key, requested_relationship, destination_key in spec["connections"]:
        source = processors[source_key]
        destination = processors[destination_key]
        selected_relationship = relationship_name(source, requested_relationship)
        client.request(
            "POST",
            f"/process-groups/{group_id}/connections",
            payload={
                "revision": {"version": 0},
                "component": {
                    "name": (
                        f"{source['name']} [{selected_relationship}] "
                        f"to {destination['name']}"
                    ),
                    "source": {
                        "id": source["id"],
                        "groupId": group_id,
                        "type": "PROCESSOR",
                    },
                    "destination": {
                        "id": destination["id"],
                        "groupId": group_id,
                        "type": "PROCESSOR",
                    },
                    "selectedRelationships": [selected_relationship],
                    "bends": bends_by_connection.get(
                        (source_key, requested_relationship, destination_key), []
                    ),
                    "flowFileExpiration": "0 sec",
                    "backPressureObjectThreshold": 1000,
                    "backPressureDataSizeThreshold": "100 MB",
                },
            },
        )


def synchronize_connection_bends(
    client: NifiClient,
    group_id: str,
    spec: dict[str, Any],
    processors_by_key: dict[str, dict[str, Any]],
) -> None:
    desired_by_connection: dict[tuple[str, str, str], list[dict[str, float]]] = {}
    for (source_key, relationship, destination_key), bends in connection_bends(
        spec
    ).items():
        source = processors_by_key[source_key]
        destination = processors_by_key[destination_key]
        desired_by_connection[
            (
                source["id"],
                relationship_name(source, relationship).casefold(),
                destination["id"],
            )
        ] = bends

    response = client.request("GET", f"/process-groups/{group_id}/connections")
    for entity in response.get("connections", []):
        component = entity["component"]
        relationships = component.get("selectedRelationships", [])
        if len(relationships) != 1:
            continue
        key = (
            component["source"]["id"],
            relationships[0].casefold(),
            component["destination"]["id"],
        )
        desired = desired_by_connection.get(key, [])
        if component.get("bends", []) == desired:
            continue
        client.request(
            "PUT",
            f"/connections/{entity['id']}",
            payload={
                "revision": revision(entity),
                "component": {"id": entity["id"], "bends": desired},
            },
        )


def group_processors(client: NifiClient, group_id: str) -> list[dict[str, Any]]:
    response = client.request("GET", f"/process-groups/{group_id}/processors")
    return response.get("processors", [])


def validate_existing_group(
    client: NifiClient, group_id: str, spec: dict[str, Any]
) -> None:
    expected = {item["name"] for item in spec["processors"]}
    processor_entities = group_processors(client, group_id)
    actual = {entity.get("component", {}).get("name") for entity in processor_entities}
    missing = expected - actual
    if missing:
        raise NifiError(
            "Existing process group is incomplete; missing processors: "
            + ", ".join(sorted(missing))
        )

    processors_by_name = {
        entity["component"]["name"]: entity["component"]
        for entity in processor_entities
    }
    processors_by_key = {
        item["key"]: processors_by_name[item["name"]] for item in spec["processors"]
    }
    response = client.request("GET", f"/process-groups/{group_id}/connections")
    actual_connections = {
        (
            entity["component"]["source"]["id"],
            relationship.casefold(),
            entity["component"]["destination"]["id"],
        )
        for entity in response.get("connections", [])
        for relationship in entity["component"].get("selectedRelationships", [])
    }
    missing_connections: list[str] = []
    for source_key, requested_relationship, destination_key in spec["connections"]:
        source = processors_by_key[source_key]
        destination = processors_by_key[destination_key]
        expected_connection = (
            source["id"],
            relationship_name(source, requested_relationship).casefold(),
            destination["id"],
        )
        if expected_connection not in actual_connections:
            missing_connections.append(
                f"{source['name']} [{requested_relationship}] to {destination['name']}"
            )
    if missing_connections:
        raise NifiError(
            "Existing process group is incomplete; reset the NiFi flow volume. "
            "Missing connections: " + ", ".join(missing_connections)
        )
    synchronize_connection_bends(client, group_id, spec, processors_by_key)


def start_process_group(client: NifiClient, group_id: str) -> None:
    client.request(
        "PUT",
        f"/flow/process-groups/{group_id}",
        payload={"id": group_id, "state": "RUNNING"},
    )


def start_configured_processors(
    client: NifiClient, group_id: str, spec: dict[str, Any]
) -> None:
    manual_triggers = set(spec["flow"].get("manual_triggers", []))
    if not manual_triggers:
        start_process_group(client, group_id)
        return

    for entity in group_processors(client, group_id):
        component = entity["component"]
        expected_state = (
            "STOPPED" if component["name"] in manual_triggers else "RUNNING"
        )
        if component.get("state") == expected_state:
            continue
        client.request(
            "PUT",
            f"/processors/{entity['id']}/run-status",
            payload={"revision": revision(entity), "state": expected_state},
        )
        wait_for_processor_state(client, entity["id"], expected_state)


def wait_for_processor_state(
    client: NifiClient, processor_id: str, expected_state: str, timeout: int = 30
) -> dict[str, Any]:
    deadline = time.monotonic() + timeout
    entity: dict[str, Any] = {}
    while time.monotonic() < deadline:
        entity = client.request("GET", f"/processors/{processor_id}")
        if entity.get("component", {}).get("state") == expected_state:
            return entity
        time.sleep(1)
    raise NifiError(
        f"Processor {processor_id} did not reach state {expected_state}: {entity}"
    )


def run_trigger_once(client: NifiClient, group_id: str, trigger_name: str) -> str:
    trigger = next(
        (
            entity
            for entity in group_processors(client, group_id)
            if entity.get("component", {}).get("name") == trigger_name
        ),
        None,
    )
    if trigger is None:
        raise NifiError(f"Trigger processor not found: {trigger_name}")

    processor_id = trigger["id"]
    if trigger["component"].get("state") != "STOPPED":
        client.request(
            "PUT",
            f"/processors/{processor_id}/run-status",
            payload={"revision": revision(trigger), "state": "STOPPED"},
        )
        trigger = wait_for_processor_state(client, processor_id, "STOPPED")

    client.request(
        "PUT",
        f"/processors/{processor_id}/run-status",
        payload={"revision": revision(trigger), "state": "RUN_ONCE"},
    )
    return processor_id


def set_trigger_state(
    client: NifiClient, group_id: str, trigger_name: str, state: str
) -> str:
    trigger = next(
        (
            entity
            for entity in group_processors(client, group_id)
            if entity.get("component", {}).get("name") == trigger_name
        ),
        None,
    )
    if trigger is None:
        raise NifiError(f"Trigger processor not found: {trigger_name}")
    if trigger["component"].get("state") != state:
        client.request(
            "PUT",
            f"/processors/{trigger['id']}/run-status",
            payload={"revision": revision(trigger), "state": state},
        )
        wait_for_processor_state(client, trigger["id"], state)
    return trigger["id"]


def validate_processors(client: NifiClient, group_id: str) -> None:
    invalid: list[str] = []
    for entity in group_processors(client, group_id):
        component = entity["component"]
        if component.get("validationStatus") == "INVALID":
            errors = "; ".join(component.get("validationErrors", []))
            invalid.append(f"{component['name']}: {errors}")
    if invalid:
        raise NifiError("Invalid NiFi processors:\n- " + "\n- ".join(invalid))


def provision(
    client: NifiClient,
    spec_path: Path,
    group_position: tuple[float, float],
) -> str:
    spec = load_spec(spec_path)
    digest = spec_digest(spec_path)
    context = create_parameter_context(client, spec["parameter_context"])
    context_id = context.get("id") or context["component"]["id"]

    existing = find_process_group(client, spec["flow"]["name"])
    group = create_process_group(client, spec, context_id, digest, group_position)
    group = set_process_group_position(client, group, group_position)
    group_id = group.get("id") or group["component"]["id"]
    if existing is not None:
        validate_existing_group(client, group_id, spec)
        validate_processors(client, group_id)
        start_configured_processors(client, group_id, spec)
        return group_id

    services = create_controller_services(client, group_id, spec)
    wait_for_services(client, services)
    processors = create_processors(client, group_id, spec, services)
    create_connections(client, group_id, spec, processors)
    validate_processors(client, group_id)
    start_configured_processors(client, group_id, spec)
    return group_id


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--url", default=os.getenv("NIFI_API_URL", "https://localhost:8443/nifi-api")
    )
    parser.add_argument(
        "--username",
        default=os.getenv("NIFI_USERNAME", "plantbridge-admin"),
    )
    parser.add_argument(
        "--password",
        default=os.getenv("NIFI_PASSWORD", "plantbridge_nifi_dev_2026"),
    )
    parser.add_argument("--spec", type=Path, default=DEFAULT_SPEC)
    parser.add_argument(
        "--group-position",
        type=parse_position,
        default=(0.0, 0.0),
        metavar="X,Y",
        help="Root-canvas position for the managed process group",
    )
    parser.add_argument("--wait-seconds", type=int, default=300)
    parser.add_argument(
        "--run-once",
        action="store_true",
        help="Stop the periodic trigger and request one immediate poll",
    )
    parser.add_argument(
        "--trigger",
        help="Processor name to run once; defaults to flow.run_once_trigger",
    )
    parser.add_argument(
        "--start-trigger",
        help="Start one manual trigger continuously after provisioning",
    )
    parser.add_argument(
        "--stop-trigger",
        help="Stop one manual trigger after provisioning",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    client = NifiClient(args.url, args.username, args.password)
    try:
        spec = load_spec(args.spec)
        client.wait_until_ready(args.wait_seconds)
        group_id = provision(client, args.spec, args.group_position)
        if args.run_once:
            trigger_name = args.trigger or spec["flow"].get("run_once_trigger")
            if trigger_name is None and args.spec.resolve() == DEFAULT_SPEC.resolve():
                trigger_name = "Trigger Telemetry Poll"
            if not trigger_name:
                raise NifiError(
                    "--run-once requires --trigger or flow.run_once_trigger"
                )
            processor_id = run_trigger_once(client, group_id, trigger_name)
            print(f"{trigger_name} requested once: {processor_id}")
        if args.start_trigger:
            processor_id = set_trigger_state(
                client, group_id, args.start_trigger, "RUNNING"
            )
            print(f"{args.start_trigger} started: {processor_id}")
        if args.stop_trigger:
            processor_id = set_trigger_state(
                client, group_id, args.stop_trigger, "STOPPED"
            )
            print(f"{args.stop_trigger} stopped: {processor_id}")
    except (NifiError, OSError, json.JSONDecodeError, KeyError) as error:
        print(f"NiFi bootstrap failed: {error}", file=sys.stderr)
        return 1
    print(f"{spec['flow']['name']} process group is provisioned: {group_id}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
