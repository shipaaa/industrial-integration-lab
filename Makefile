.PHONY: start start-api stop load-reference replay-reference verify-reference test test-api test-postgres-local

start:
	docker compose up --detach --wait postgres

start-api:
	docker compose up --detach --build --wait source-simulator

stop:
	docker compose down

load-reference:
	./scripts/load-reference.sh

replay-reference: load-reference verify-reference

verify-reference:
	./scripts/verify-reference.sh

test:
	python3 -m unittest discover --start-directory tests --verbose

test-api:
	docker build --target test --tag plantbridge-source-simulator-test --file source-simulator/Dockerfile .
	docker run --rm plantbridge-source-simulator-test

test-postgres-local:
	./scripts/test-postgres-local.sh
