.PHONY: lint test-aws up down reset logs smoke-test

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

smoke-test:
	tests/postgres-init.sh
	tests/s3-access.sh
	tests/nessie-service.sh
