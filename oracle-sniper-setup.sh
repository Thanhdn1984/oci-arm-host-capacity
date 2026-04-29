#!/bin/bash
# ============================================================
#  Oracle ARM Sniper - Auto Setup
#  Repo: github.com/Thanhdn1984/oci-arm-host-capacity
#  Dùng GitHub CLI để set secrets tự động
#  Chạy script này trên bất kỳ VPS nào
# ============================================================

set -e

GITHUB_REPO="Thanhdn1984/oci-arm-host-capacity"
BOLD="\e[1m"; GREEN="\e[32m"; YELLOW="\e[33m"; RED="\e[31m"; NC="\e[0m"

echo -e "${BOLD}================================================${NC}"
echo -e "${BOLD}   Oracle ARM Sniper - Auto Setup v1.0         ${NC}"
echo -e "${BOLD}================================================${NC}"
echo ""

# ─── Kiểm tra GitHub CLI ─────────────────────────────────
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
    echo -e "${YELLOW}🔑 Cần đăng nhập GitHub. Nhập Personal Access Token (cần quyền repo + secrets):${NC}"
    echo -e "   Tạo token tại: ${BOLD}https://github.com/settings/tokens/new${NC}"
    echo -e "   Cần tick: ${BOLD}repo${NC} (toàn bộ) và ${BOLD}workflow${NC}"
    echo ""
    read -rsp "   Paste token vào đây (không hiển thị): " GH_TOKEN
    echo ""
    echo "$GH_TOKEN" | gh auth login --with-token
fi

echo -e "${GREEN}✅ GitHub đã đăng nhập${NC}"
echo ""

# ─── Nhập thông tin Oracle account ───────────────────────
echo -e "${BOLD}📋 Nhập thông tin Oracle Cloud account:${NC}"
echo -e "   (Lấy từ Oracle Console → Profile → API Keys)\n"

read -rp "   OCI_USER_OCID       : " OCI_USER_OCID
read -rp "   OCI_TENANCY_OCID    : " OCI_TENANCY_OCID
read -rp "   OCI_KEY_FINGERPRINT : " OCI_KEY_FINGERPRINT
read -rp "   OCI_REGION          (vd: ap-singapore-1): " OCI_REGION
read -rp "   OCI_SUBNET_ID       : " OCI_SUBNET_ID
read -rp "   OCI_IMAGE_ID        (Ubuntu ARM): " OCI_IMAGE_ID
read -rp "   OCI_SSH_PUBLIC_KEY  (nội dung ~/.ssh/id_rsa.pub): " OCI_SSH_PUBLIC_KEY
read -rp "   OCI_OCPUS           (mặc định 4): " OCI_OCPUS
OCI_OCPUS=${OCI_OCPUS:-4}
read -rp "   OCI_MEMORY_IN_GBS   (mặc định 24): " OCI_MEMORY_IN_GBS
OCI_MEMORY_IN_GBS=${OCI_MEMORY_IN_GBS:-24}

echo ""
echo -e "${BOLD}🔑 Dán nội dung file OCI Private Key (.pem):${NC}"
echo -e "   (Paste rồi nhấn Enter, sau đó gõ ${BOLD}DONE${NC} trên dòng mới)"
OCI_PRIVATE_KEY=""
while IFS= read -r line; do
    [[ "$line" == "DONE" ]] && break
    OCI_PRIVATE_KEY+="$line"$'\n'
done

# ─── Set secrets lên GitHub ──────────────────────────────
echo ""
echo -e "${YELLOW}⬆️  Đang đẩy secrets lên GitHub repo...${NC}"

set_secret() {
    local name="$1"
    local value="$2"
    echo -n "   $name... "
    echo "$value" | gh secret set "$name" --repo "$GITHUB_REPO"
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
echo -e "${YELLOW}⚡ Kích hoạt GitHub Actions workflow...${NC}"
gh workflow enable --repo "$GITHUB_REPO" 2>/dev/null || true
gh workflow run run.yml --repo "$GITHUB_REPO" 2>/dev/null || \
gh workflow run tests.yml --repo "$GITHUB_REPO" 2>/dev/null || \
echo -e "${YELLOW}   (Workflow sẽ tự chạy theo schedule)${NC}"

# ─── Xong ────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}================================================${NC}"
echo -e "${GREEN}✅ Xong! Script đã cấu hình xong.${NC}"
echo -e "${GREEN}   Workflow chạy mỗi 5 phút tự động snipe ARM.${NC}"
echo ""
echo -e "   Theo dõi tại:${NC}"
echo -e "   ${BOLD}https://github.com/${GITHUB_REPO}/actions${NC}"
echo -e "${BOLD}${GREEN}================================================${NC}"
echo ""
echo -e "${YELLOW}💡 Lần sau dùng account Oracle khác:${NC}"
echo -e "   Chỉ cần chạy lại script này, nhập thông tin mới là xong."
