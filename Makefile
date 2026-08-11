.PHONY: start start-api start-nifi bootstrap-nifi verify-nifi replay-nifi stop load-reference replay-reference verify-reference migrate-telemetry load-telemetry verify-telemetry replay-telemetry test test-api test-telemetry-db test-postgres-local

start:
	docker compose up --detach --wait postgres

start-api:
	docker compose up --detach --build --wait source-simulator

start-nifi:
	docker compose up --detach --build --wait postgres source-simulator nifi
	./scripts/bootstrap-nifi.py

bootstrap-nifi:
	./scripts/bootstrap-nifi.py

verify-nifi:
	./scripts/verify-nifi-telemetry.sh

replay-nifi:
	./scripts/replay-nifi-telemetry.sh

stop:
	docker compose down

load-reference:
	./scripts/load-reference.sh

replay-reference: load-reference verify-reference

verify-reference:
	./scripts/verify-reference.sh

migrate-telemetry:
	./scripts/apply-telemetry-db.sh

load-telemetry:
	./scripts/load-telemetry.sh

verify-telemetry:
	./scripts/verify-telemetry.sh

replay-telemetry: load-telemetry
	docker compose exec -T postgres psql --username plantbridge --dbname plantbridge --set ON_ERROR_STOP=1 --file /db/test/verify_telemetry_replay.sql

test:
	python3 -m unittest discover --start-directory tests --verbose

test-api:
	docker build --target test --tag plantbridge-source-simulator-test --file source-simulator/Dockerfile .
	docker run --rm plantbridge-source-simulator-test

test-telemetry-db:
	./scripts/test-telemetry-db.sh

test-postgres-local:
	./scripts/test-postgres-local.sh
