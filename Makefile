.PHONY: lint test-aws up down reset logs sql-nessie smoke-test

lint:
	tests/lint.sh
	tests/check-no-secrets.sh

test-aws:
	tests/test-iam-policies.sh
	tests/test-aws-setup.sh
	tests/test-aws-teardown.sh

# Every profile, so that the catalogs that are off are also stopped or removed.
ALL_PROFILES = COMPOSE_PROFILES='*'

up:
	mkdir -p secrets
	@on=$$(docker compose config --services) || exit 1; \
	off=$$($(ALL_PROFILES) docker compose config --services | grep -vxF "$$on" || true); \
	if [ -n "$$off" ]; then $(ALL_PROFILES) docker compose stop $$off; fi
	docker compose up -d --build --wait

down:
	$(ALL_PROFILES) docker compose down

reset:
	$(ALL_PROFILES) docker compose down -v

logs:
	docker compose logs -f --tail=200

sql-nessie:
	docker compose exec spark spark-sql --conf spark.sql.defaultCatalog=nessie

smoke-test:
	tests/smoke-test.sh
