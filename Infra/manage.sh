#!/bin/bash
set -e

TF_DIR="./Terraform"
ANSIBLE_DIR="./Ansible"

usage() {
    echo "Usage: $0 {up|down|ansible}"
    echo "  up      - Provision infrastructure and run Ansible"
    echo "  down    - Destroy all infrastructure"
    echo "  ansible - Re-run Ansible only (no Terraform changes)"
    exit 1
}

[[ -z "$1" ]] && usage

case "$1" in
    up)
        echo "=== Starting Deployment ==="

        # Terraform
        echo "[1/3] Running Terraform..."
        cd "$TF_DIR"
        terraform init -input=false
        terraform apply -auto-approve

        # Extract outputs
        echo "[2/3] Extracting IPs..."
        CONTROL_PLANE=$(terraform output -raw control_plane_ip)
        WORKERS=$(terraform output -json worker_ips | jq -r '.[]')
        USER=$(terraform output -raw ssh_user)
        KEY=$(terraform output -raw ssh_key_path)

        # Generate inventory
        echo "[3/3] Running Ansible..."
        cd "../$ANSIBLE_DIR"
        cat > inventory.ini <<EOF
[control_plane]
$CONTROL_PLANE ansible_user=$USER ansible_ssh_private_key_file=$KEY

[workers]
$(for ip in $WORKERS; do echo "$ip ansible_user=$USER ansible_ssh_private_key_file=$KEY"; done)

[all:vars]
ansible_python_interpreter=/usr/bin/python3
EOF

        sleep 10
        ansible-playbook -i inventory.ini plybk.yaml
        echo "=== Deployment Complete ==="
        ;;

    down)
        echo "=== Destroying Infrastructure ==="
        cd "$TF_DIR"
        terraform destroy -auto-approve
        rm -f "../$ANSIBLE_DIR/inventory.ini"
        echo "=== Destroy Complete ==="
        ;;

    ansible)
        echo "=== Re-running Ansible Only ==="
        cd "$ANSIBLE_DIR"
        if [[ ! -f inventory.ini ]]; then
            echo "Error: inventory.ini not found. Run '$0 up' first."
            exit 1
        fi
        ansible-playbook -i inventory.ini plybk.yaml
        echo "=== Ansible Complete ==="
        ;;

    *)
        usage
        ;;
esac
