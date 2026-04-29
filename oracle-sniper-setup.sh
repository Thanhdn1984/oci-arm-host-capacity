#!/bin/bash
# ============================================================
#  Oracle ARM Sniper - Auto Setup v2.0
#  Repo: github.com/Thanhdn1984/oci-arm-host-capacity
#  Dùng file oci-config.env thay vì gõ tay
# ============================================================

set -e

GITHUB_REPO="Thanhdn1984/oci-arm-host-capacity"
BOLD="\e[1m"; GREEN="\e[32m"; YELLOW="\e[33m"; RED="\e[31m"; NC="\e[0m"
CONFIG_FILE="$HOME/oci-config.env"

echo -e "${BOLD}================================================${NC}"
echo -e "${BOLD}   Oracle ARM Sniper - Auto Setup v2.0         ${NC}"
echo -e "${BOLD}================================================${NC}"
echo ""

# ─── Tạo file config mẫu nếu chưa có ────────────────────
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${YELLOW}📝 Tạo file config mẫu tại $CONFIG_FILE${NC}"
    cat > "$CONFIG_FILE" << 'EOF'
# ================================================
# Oracle Cloud Config - Điền thông tin vào đây
# Sau đó chạy lại: ./oracle-sniper-setup.sh
# ================================================

OCI_USER_OCID=ocid1.user.oc1..xxxxxxxxxx
OCI_TENANCY_OCID=ocid1.tenancy.oc1..xxxxxxxxxx
OCI_KEY_FINGERPRINT=xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx
OCI_REGION=ap-singapore-1
OCI_SUBNET_ID=ocid1.subnet.oc1..xxxxxxxxxx
OCI_IMAGE_ID=ocid1.image.oc1..xxxxxxxxxx
OCI_SSH_PUBLIC_KEY=ssh-rsa AAAAB3Nza...
OCI_OCPUS=4
OCI_MEMORY_IN_GBS=24
OCI_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----
PASTE_PRIVATE_KEY_HERE
-----END PRIVATE KEY-----"
EOF
    echo -e "${GREEN}✅ Đã tạo file: $CONFIG_FILE${NC}"
    echo -e "${YELLOW}👉 Mở file và điền thông tin Oracle vào:${NC}"
    echo -e "   ${BOLD}nano $CONFIG_FILE${NC}"
    echo ""
    echo -e "   Sau đó chạy lại: ${BOLD}./oracle-sniper-setup.sh${NC}"
    exit 0
fi

# ─── Đọc config file ─────────────────────────────────────
echo -e "${YELLOW}📂 Đọc config từ $CONFIG_FILE ...${NC}"
source "$CONFIG_FILE"

# ─── Kiểm tra các field bắt buộc ─────────────────────────
MISSING=0
for var in OCI_USER_OCID OCI_TENANCY_OCID OCI_KEY_FINGERPRINT OCI_REGION OCI_SUBNET_ID OCI_IMAGE_ID OCI_SSH_PUBLIC_KEY OCI_PRIVATE_KEY; do
    val="${!var}"
    if [[ -z "$val" || "$val" == *"xxxxxxxxxx"* || "$val" == *"PASTE_"* ]]; then
        echo -e "${RED}❌ Chưa điền: $var${NC}"
        MISSING=1
    fi
done

if [ $MISSING -eq 1 ]; then
    echo ""
    echo -e "${YELLOW}👉 Mở file và điền đầy đủ thông tin:${NC}"
    echo -e "   ${BOLD}nano $CONFIG_FILE${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Config hợp lệ${NC}"
echo ""

# ─── Kiểm tra / cài GitHub CLI ───────────────────────────
if ! command -v gh &>/dev/null; then
    echo -e "${YELLOW}📦 Cài GitHub CLI...${NC}"
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | \
        sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] \
        https://cli.github.com/packages stable main" | \
        sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    sudo apt update -qq && sudo apt install -y gh
fi

# ─── Đăng nhập GitHub ────────────────────────────────────
if ! gh auth status &>/dev/null; then
    echo -e "${YELLOW}🔑 Cần đăng nhập GitHub.${NC}"
    echo -e "   Tạo token tại: ${BOLD}https://github.com/settings/tokens/new${NC}"
    echo -e "   Cần tick: ${BOLD}repo${NC} và ${BOLD}workflow${NC}"
    echo ""
    read -rsp "   Paste token vào đây: " GH_TOKEN
    echo ""
    echo "$GH_TOKEN" | gh auth login --with-token
fi

echo -e "${GREEN}✅ GitHub đã đăng nhập${NC}"
echo ""

# ─── Set secrets lên GitHub ──────────────────────────────
echo -e "${YELLOW}⬆️  Đang đẩy secrets lên GitHub...${NC}"

set_secret() {
    local name="$1"
    local value="$2"
    echo -n "   $name... "
    printf '%s' "$value" | gh secret set "$name" --repo "$GITHUB_REPO"
    echo -e "${GREEN}✓${NC}"
}

set_secret "OCI_USER_OCID"       "$OCI_USER_OCID"
set_secret "OCI_TENANCY_OCID"    "$OCI_TENANCY_OCID"
set_secret "OCI_KEY_FINGERPRINT" "$OCI_KEY_FINGERPRINT"
set_secret "OCI_REGION"          "$OCI_REGION"
set_secret "OCI_SUBNET_ID"       "$OCI_SUBNET_ID"
set_secret "OCI_IMAGE_ID"        "$OCI_IMAGE_ID"
set_secret "OCI_SSH_PUBLIC_KEY"  "$OCI_SSH_PUBLIC_KEY"
set_secret "OCI_PRIVATE_KEY"     "$OCI_PRIVATE_KEY"
set_secret "OCI_OCPUS"           "$OCI_OCPUS"
set_secret "OCI_MEMORY_IN_GBS"   "$OCI_MEMORY_IN_GBS"

# ─── Kích hoạt Actions ───────────────────────────────────
echo ""
echo -e "${YELLOW}⚡ Kích hoạt GitHub Actions...${NC}"
gh workflow enable --repo "$GITHUB_REPO" 2>/dev/null || true
gh workflow run run.yml --repo "$GITHUB_REPO" 2>/dev/null || \
gh workflow run tests.yml --repo "$GITHUB_REPO" 2>/dev/null || \
echo -e "${YELLOW}   Workflow sẽ tự chạy theo schedule${NC}"

# ─── Xong ────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}================================================${NC}"
echo -e "${GREEN}✅ Xong! Workflow đang snipe ARM mỗi 5 phút.${NC}"
echo ""
echo -e "   Theo dõi tại:${NC}"
echo -e "   ${BOLD}https://github.com/${GITHUB_REPO}/actions${NC}"
echo -e "${BOLD}${GREEN}================================================${NC}"
echo ""
echo -e "${YELLOW}💡 Lần sau dùng account Oracle khác:${NC}"
echo -e "   1. nano ~/oci-config.env  ← sửa thông tin mới"
echo -e "   2. ./oracle-sniper-setup.sh  ← chạy lại"
