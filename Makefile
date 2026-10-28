.PHONY: lint test-aws

lint:
	tests/lint.sh

test-aws:
	tests/test-iam-policies.sh
	tests/test-aws-setup.sh
	tests/test-aws-teardown.sh
