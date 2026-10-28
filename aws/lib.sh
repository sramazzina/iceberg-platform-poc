# Shared helpers for aws/setup.sh and aws/teardown.sh. Source this file; do not run it.

VM_POLICY_NAME=iceberg-lab-vm
POLARIS_ROLE_NAME=polaris-s3-access
POLARIS_POLICY_NAME=polaris-s3-access

# render_template FILE
# Prints FILE with every ${NAME} placeholder replaced by the value of the shell
# variable NAME. Returns 1 when a placeholder has no value.
render_template() {
  local content name
  content=$(<"$1")
  while [[ $content =~ \$\{([A-Z_][A-Z0-9_]*)\} ]]; do
    name=${BASH_REMATCH[1]}
    if [[ -z ${!name:-} ]]; then
      echo "render_template: variable $name is not set (in $1)" >&2
      return 1
    fi
    if [[ ${!name} == *'${'* ]]; then
      echo "render_template: value of $name contains '\${' (in $1)" >&2
      return 1
    fi
    content=${content//"\${$name}"/"${!name}"}
  done
  printf '%s\n' "$content"
}

# vm_role_name INSTANCE_ID
# Prints the name of the IAM role in the instance profile of the instance.
vm_role_name() {
  local profile_arn profile_name role_name
  profile_arn=$(aws ec2 describe-instances --instance-ids "$1" \
    --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn' --output text) || return 1
  if [[ -z $profile_arn || $profile_arn == None ]]; then
    echo "Instance $1 has no instance profile. Attach one, then run again." >&2
    return 1
  fi
  profile_name=${profile_arn##*/}
  role_name=$(aws iam get-instance-profile --instance-profile-name "$profile_name" \
    --query 'InstanceProfile.Roles[0].RoleName' --output text) || return 1
  if [[ -z $role_name || $role_name == None ]]; then
    echo "Instance profile $profile_name has no role. Add one, then run again." >&2
    return 1
  fi
  printf '%s\n' "$role_name"
}
