.PHONY: lint test-aws

lint:
	tests/lint.sh

test-aws:
	tests/test-iam-policies.sh
