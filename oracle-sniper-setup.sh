#!/bin/bash
# ============================================================
#  Oracle ARM Sniper - Auto Setup v3.0
#  - Tự động lấy Subnet ID và Image ID qua OCI CLI
#  - Chọn OCPU (1-4) và RAM (6-24GB)
#  - Set secrets lên GitHub Actions tự động
# ============================================================

set -e
GITHUB_REPO="Thanhdn1984/oci-arm-host-capacity"
BOLD="\e[1m"; GREEN="\e[32m"; YELLOW="\e[33m"; RED="\e[31m"; CYAN="\e[36m"; NC="\e[0m"

echo -e "${BOLD}================================================${NC}"
echo -e "${BOLD}   Oracle ARM Sniper v3.0 - Auto Setup         ${NC}"
echo -e "${BOLD}================================================${NC}"
echo ""

if ! command -v oci &>/dev/null; then
    echo -e "${YELLOW}📦 Cài OCI CLI...${NC}"
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)" -- --accept-all-defaults 2>&1 | tail -5
    export PATH="$PATH:$HOME/bin"
    echo 'export PATH="$PATH:$HOME/bin"' >> ~/.bashrc
fi
export PATH="$PATH:$HOME/bin"
echo -e "${GREEN}✅ OCI CLI sẵn sàng${NC}"

mkdir -p ~/.oci
OCI_CONFIG="$HOME/.oci/config"
OCI_KEY="$HOME/.oci/oci_api_key.pem"

if [ ! -f "$OCI_CONFIG" ] || ! grep -q "user=ocid1" "$OCI_CONFIG" 2>/dev/null; then
    echo ""
    echo -e "${BOLD}📋 Paste nội dung OCI config (từ Oracle Console → API Keys → View):${NC}"
    echo -e "   ${CYAN}Paste rồi nhấn Enter, gõ DONE trên dòng mới${NC}"
    echo ""
    OCI_CONFIG_CONTENT=""
    while IFS= read -r line; do
        [[ "$line" == "DONE" ]] && break
        OCI_CONFIG_CONTENT+="$line"$'\n'
    done
    echo "$OCI_CONFIG_CONTENT" | sed "s|key_file=.*|key_file=$OCI_KEY|g" > "$OCI_CONFIG"
    echo -e "${GREEN}✅ Config đã lưu${NC}"
fi

if [ ! -f "$OCI_KEY" ]; then
    echo ""
    echo -e "${BOLD}🔑 Paste nội dung Private Key (.pem):${NC}"
    echo -e "   ${CYAN}Paste toàn bộ kể cả -----BEGIN/END-----, gõ DONE trên dòng mới${NC}"
    echo ""
    OCI_KEY_CONTENT=""
    while IFS= read -r line; do
        [[ "$line" == "DONE" ]] && break
        OCI_KEY_CONTENT+="$line"$'\n'
    done
    echo "$OCI_KEY_CONTENT" > "$OCI_KEY"
    chmod 600 "$OCI_KEY"
    echo -e "${GREEN}✅ Private key đã lưu${NC}"
fi

OCI_USER=$(grep "^user=" "$OCI_CONFIG" | cut -d= -f2 | tr -d ' ')
OCI_TENANCY=$(grep "^tenancy=" "$OCI_CONFIG" | cut -d= -f2 | tr -d ' ')
OCI_FINGERPRINT=$(grep "^fingerprint=" "$OCI_CONFIG" | cut -d= -f2 | tr -d ' ')
OCI_REGION=$(grep "^region=" "$OCI_CONFIG" | cut -d= -f2 | tr -d ' ')

echo ""
echo -e "${CYAN}📌 Thông tin account:${NC}"
echo -e "   User    : $OCI_USER"
echo -e "   Tenancy : $OCI_TENANCY"
echo -e "   Region  : $OCI_REGION"
echo -e "   Key     : $OCI_FINGERPRINT"

echo ""
echo -e "${YELLOW}🔍 Kiểm tra kết nối Oracle...${NC}"
if ! oci iam region list 2>/dev/null | grep -q "ap-singapore\|frankfurt\|ashburn\|phoenix"; then
    echo -e "${RED}❌ Không kết nối được Oracle.${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Kết nối Oracle OK${NC}"

echo ""
echo -e "${YELLOW}🔍 Lấy danh sách Subnets...${NC}"
SUBNETS=$(oci network subnet list --compartment-id "$OCI_TENANCY" --region "$OCI_REGION" 2>/dev/null)
SUBNET_COUNT=$(echo "$SUBNETS" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('data',[])))" 2>/dev/null || echo "0")

if [ "$SUBNET_COUNT" -eq 0 ]; then
    echo -e "${RED}❌ Không tìm thấy subnet. Nhập thủ công:${NC}"
    read -rp "   OCI_SUBNET_ID: " OCI_SUBNET_ID
else
    echo ""
    echo -e "${BOLD}📋 Chọn Subnet:${NC}"
    echo "$SUBNETS" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for i,s in enumerate(d.get('data',[])):
    print(f\"  [{i+1}] {s.get('display-name','?')} | {s.get('cidr-block','?')}\")
"
    read -rp "   Chọn số [1-$SUBNET_COUNT]: " SUBNET_CHOICE
    SUBNET_CHOICE=$((SUBNET_CHOICE - 1))
    OCI_SUBNET_ID=$(echo "$SUBNETS" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['data'][$SUBNET_CHOICE]['id'])")
    echo -e "${GREEN}✅ Subnet OK${NC}"
fi

echo ""
echo -e "${YELLOW}🔍 Tìm Ubuntu ARM images...${NC}"
IMAGES=$(oci compute image list --compartment-id "$OCI_TENANCY" --region "$OCI_REGION" --shape "VM.Standard.A1.Flex" --operating-system "Canonical Ubuntu" --sort-by TIMECREATED --sort-order DESC 2>/dev/null)
IMAGE_COUNT=$(echo "$IMAGES" | python3 -c "import json,sys; d=json.load(sys.stdin); print(min(5,len(d.get('data',[]))))" 2>/dev/null || echo "0")

if [ "$IMAGE_COUNT" -eq 0 ]; then
    echo -e "${RED}❌ Không tìm thấy image. Nhập thủ công:${NC}"
    read -rp "   OCI_IMAGE_ID: " OCI_IMAGE_ID
else
    echo ""
    echo -e "${BOLD}📋 Chọn Ubuntu Image (ARM):${NC}"
    echo "$IMAGES" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for i,img in enumerate(d.get('data',[])[:5]):
    print(f\"  [{i+1}] {img.get('display-name','?')} ({img.get('time-created','?')[:10]})\")
"
    read -rp "   Chọn số [1-$IMAGE_COUNT] (1=mới nhất): " IMAGE_CHOICE
    IMAGE_CHOICE=$((IMAGE_CHOICE - 1))
    OCI_IMAGE_ID=$(echo "$IMAGES" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['data'][$IMAGE_CHOICE]['id'])")
    echo -e "${GREEN}✅ Image OK${NC}"
fi

echo ""
echo -e "${BOLD}⚙️  Cấu hình instance (free tier tối đa: 4 OCPU / 24GB):${NC}"
echo ""
echo "   [1] 1 OCPU  [2] 2 OCPU  [3] 3 OCPU  [4] 4 OCPU (tối đa)"
read -rp "   Chọn OCPU [1-4] (Enter=4): " CPU_CHOICE
case $CPU_CHOICE in
    1) OCI_OCPUS=1 ;; 2) OCI_OCPUS=2 ;; 3) OCI_OCPUS=3 ;; *) OCI_OCPUS=4 ;;
esac

echo ""
echo "   [1] 6GB  [2] 12GB  [3] 16GB  [4] 24GB (tối đa)"
read -rp "   Chọn RAM [1-4] (Enter=4): " RAM_CHOICE
case $RAM_CHOICE in
    1) OCI_MEMORY_IN_GBS=6 ;; 2) OCI_MEMORY_IN_GBS=12 ;; 3) OCI_MEMORY_IN_GBS=16 ;; *) OCI_MEMORY_IN_GBS=24 ;;
esac
echo -e "${GREEN}✅ ${OCI_OCPUS} OCPU / ${OCI_MEMORY_IN_GBS}GB RAM${NC}"

echo ""
if [ -f ~/.ssh/id_rsa.pub ]; then
    OCI_SSH_PUBLIC_KEY=$(cat ~/.ssh/id_rsa.pub)
    echo -e "${GREEN}✅ SSH key: ~/.ssh/id_rsa.pub${NC}"
elif [ -f ~/.ssh/id_ed25519.pub ]; then
    OCI_SSH_PUBLIC_KEY=$(cat ~/.ssh/id_ed25519.pub)
    echo -e "${GREEN}✅ SSH key: ~/.ssh/id_ed25519.pub${NC}"
else
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
    OCI_SSH_PUBLIC_KEY=$(cat ~/.ssh/id_rsa.pub)
    echo -e "${GREEN}✅ SSH key mới tạo${NC}"
fi

if ! command -v gh &>/dev/null; then
    echo -e "${YELLOW}📦 Cài GitHub CLI...${NC}"
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    sudo apt update -qq && sudo apt install -y gh
fi

if ! gh auth status &>/dev/null; then
    echo -e "${YELLOW}🔑 Đăng nhập GitHub:${NC}"
    echo -e "   Tạo token: https://github.com/settings/tokens/new"
    echo -e "   Tick: repo và workflow"
    read -rsp "   Paste token: " GH_TOKEN
    echo ""
    echo "$GH_TOKEN" | gh auth login --with-token
fi
echo -e "${GREEN}✅ GitHub OK${NC}"

echo ""
echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}📋 Xác nhận:  $OCI_REGION | ${OCI_OCPUS} OCPU | ${OCI_MEMORY_IN_GBS}GB${NC}"
echo -e "${CYAN}================================================${NC}"
read -rp "   Push lên GitHub? [y/N]: " CONFIRM
[[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]] && echo "Đã hủy." && exit 0

echo ""
echo -e "${YELLOW}⬆️  Đẩy secrets lên GitHub...${NC}"
set_secret() {
    echo -n "   $1... "
    printf '%s' "$2" | gh secret set "$1" --repo "$GITHUB_REPO"
    echo -e "${GREEN}✓${NC}"
}
set_secret "OCI_USER_OCID"       "$OCI_USER"
set_secret "OCI_TENANCY_OCID"    "$OCI_TENANCY"
set_secret "OCI_KEY_FINGERPRINT" "$OCI_FINGERPRINT"
set_secret "OCI_REGION"          "$OCI_REGION"
set_secret "OCI_SUBNET_ID"       "$OCI_SUBNET_ID"
set_secret "OCI_IMAGE_ID"        "$OCI_IMAGE_ID"
set_secret "OCI_SSH_PUBLIC_KEY"  "$OCI_SSH_PUBLIC_KEY"
set_secret "OCI_PRIVATE_KEY"     "$(cat $OCI_KEY)"
set_secret "OCI_OCPUS"           "$OCI_OCPUS"
set_secret "OCI_MEMORY_IN_GBS"   "$OCI_MEMORY_IN_GBS"

gh workflow enable --repo "$GITHUB_REPO" 2>/dev/null || true
gh workflow run run.yml --repo "$GITHUB_REPO" 2>/dev/null || \
gh workflow run tests.yml --repo "$GITHUB_REPO" 2>/dev/null || true

echo ""
echo -e "${GREEN}✅ Xong! Workflow snipe ARM mỗi 5 phút.${NC}"
echo -e "   👉 https://github.com/${GITHUB_REPO}/actions${NC}"
echo ""
echo -e "${YELLOW}💡 Lần sau dùng account Oracle khác:${NC}"
echo -e "   rm ~/.oci/config ~/.oci/oci_api_key.pem && ./oracle-sniper-setup.sh"
