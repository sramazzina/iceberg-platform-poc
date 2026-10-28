.PHONY: lint test-aws up down reset logs sql-nessie smoke-test

lint:
	tests/lint.sh
	tests/check-no-secrets.sh

test-aws:
	tests/test-iam-policies.sh
	tests/test-aws-setup.sh
	tests/test-aws-teardown.sh

up:
	docker compose up -d --build --wait

down:
	docker compose down

reset:
	docker compose down -v

logs:
	docker compose logs -f --tail=200

sql-nessie:
	docker compose exec spark spark-sql --conf spark.sql.defaultCatalog=nessie

smoke-test:
	tests/postgres-init.sh
	tests/s3-access.sh
	tests/nessie-service.sh
	tests/catalog-smoke.sh nessie
