.PHONY: start stop load-reference replay-reference verify-reference test test-postgres-local

start:
	docker compose up --detach --wait postgres

stop:
	docker compose down

load-reference:
	./scripts/load-reference.sh

replay-reference: load-reference verify-reference

verify-reference:
	./scripts/verify-reference.sh

test:
	python3 -m unittest discover --start-directory tests --verbose

test-postgres-local:
	./scripts/test-postgres-local.sh
