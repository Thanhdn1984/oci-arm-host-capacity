#!/bin/bash
# ============================================================
#  Oracle ARM Sniper - Auto Setup v3.1
#  - Dùng nano để paste config & private key (không bị cắt)
#  - Tự động lấy Subnet ID và Image ID
#  - Set secrets lên GitHub Actions tự động
# ============================================================

set -e
GITHUB_REPO="Thanhdn1984/oci-arm-host-capacity"
BOLD="\e[1m"; GREEN="\e[32m"; YELLOW="\e[33m"; RED="\e[31m"; CYAN="\e[36m"; NC="\e[0m"

echo -e "${BOLD}================================================${NC}"
echo -e "${BOLD}   Oracle ARM Sniper v3.1 - Auto Setup         ${NC}"
echo -e "${BOLD}================================================${NC}"
echo ""

# ─── Cài OCI CLI nếu chưa có ─────────────────────────────
if ! command -v oci &>/dev/null && [ ! -f ~/bin/oci ]; then
    echo -e "${YELLOW}📦 Cài OCI CLI (mất 2-3 phút)...${NC}"
    rm -rf ~/lib/oracle-cli 2>/dev/null || true
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)" -- --accept-all-defaults 2>&1 | tail -3
fi
export PATH="$PATH:$HOME/bin"
[ -f ~/bin/oci ] && echo -e "${GREEN}✅ OCI CLI sẵn sàng${NC}" || { echo -e "${RED}❌ Cài OCI CLI lỗi${NC}"; exit 1; }

# ─── Đảm bảo có nano ─────────────────────────────────────
if ! command -v nano &>/dev/null; then
    echo -e "${YELLOW}📦 Cài nano editor...${NC}"
    sudo apt update -qq && sudo apt install -y nano
fi

mkdir -p ~/.oci
OCI_CONFIG="$HOME/.oci/config"
OCI_KEY="$HOME/.oci/oci_api_key.pem"

# ─── Bước 1: HƯỚNG DẪN LẤY THÔNG TIN ─────────────────────
if [ ! -f "$OCI_CONFIG" ] || ! grep -q "user=ocid1" "$OCI_CONFIG" 2>/dev/null; then
    clear
    echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║  HƯỚNG DẪN LẤY OCI CONFIG VÀ PRIVATE KEY     ║${NC}"
    echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BOLD}1️⃣  ĐĂNG NHẬP ORACLE CLOUD:${NC}"
    echo -e "   👉 https://cloud.oracle.com"
    echo ""
    echo -e "${BOLD}2️⃣  VÀO TRANG API KEYS:${NC}"
    echo -e "   👉 Profile (góc trên phải) → User Settings → API Keys"
    echo ""
    echo -e "${BOLD}3️⃣  TẠO API KEY MỚI (nếu chưa có):${NC}"
    echo -e "   • Click ${BOLD}Add API Key${NC}"
    echo -e "   • Chọn ${BOLD}Generate API Key Pair${NC}"
    echo -e "   • Click ${BOLD}Download Private Key${NC} (lưu file .pem về máy)"
    echo -e "   • Click ${BOLD}Add${NC}"
    echo ""
    echo -e "${BOLD}4️⃣  LẤY CONFIG TEXT:${NC}"
    echo -e "   • Sau khi tạo, Oracle hiện cửa sổ ${BOLD}Configuration File Preview${NC}"
    echo -e "   • Copy toàn bộ block text (có dòng [DEFAULT], user=, fingerprint=, ...)"
    echo ""
    echo -e "${YELLOW}   ⚠️  QUAN TRỌNG: Phải copy đầy đủ, KHÔNG dùng 'Copy' button của Oracle${NC}"
    echo -e "${YELLOW}      mà phải BÔI ĐEN toàn bộ text rồi Cmd+C / Ctrl+C${NC}"
    echo ""
    read -rp "   Nhấn Enter để mở editor paste OCI config..." DUMMY
    
    # Mở nano để paste config
    cat > "$OCI_CONFIG" << 'TEMPLATE'
# ════════════════════════════════════════════════════
# Paste OCI config vào đây (xoá các dòng comment này)
# Format đầy đủ phải có:
#   [DEFAULT]
#   user=ocid1.user.oc1..xxxxx
#   fingerprint=xx:xx:xx:...
#   tenancy=ocid1.tenancy.oc1..xxxxx
#   region=ap-singapore-1
#   key_file=...   (sẽ được tự động sửa)
# 
# Sau khi paste: Ctrl+O → Enter → Ctrl+X
# ════════════════════════════════════════════════════

TEMPLATE
    nano "$OCI_CONFIG"
    
    # Loại bỏ comment lines, chỉnh key_file
    grep -v "^#" "$OCI_CONFIG" | grep -v "^$" > "$OCI_CONFIG.tmp"
    sed -i "s|^key_file=.*|key_file=$OCI_KEY|" "$OCI_CONFIG.tmp"
    # Đảm bảo có dòng key_file
    if ! grep -q "^key_file=" "$OCI_CONFIG.tmp"; then
        echo "key_file=$OCI_KEY" >> "$OCI_CONFIG.tmp"
    fi
    mv "$OCI_CONFIG.tmp" "$OCI_CONFIG"
    chmod 600 "$OCI_CONFIG"
    
    # Validate
    if ! grep -q "^user=ocid1" "$OCI_CONFIG" || ! grep -q "^tenancy=ocid1" "$OCI_CONFIG"; then
        echo -e "${RED}❌ Config không hợp lệ. Phải có user= và tenancy= bắt đầu bằng ocid1${NC}"
        echo -e "   File hiện tại: $OCI_CONFIG"
        cat "$OCI_CONFIG"
        exit 1
    fi
    echo -e "${GREEN}✅ Config đã lưu${NC}"
fi

# ─── Bước 2: PASTE PRIVATE KEY ───────────────────────────
if [ ! -f "$OCI_KEY" ]; then
    clear
    echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║  PASTE PRIVATE KEY (.pem)                     ║${NC}"
    echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BOLD}MỞ FILE .pem ĐÃ TẢI VỀ:${NC}"
    echo ""
    echo -e "${CYAN}Trên Mac:${NC}"
    echo -e "   • Mở Terminal trên Mac, chạy: ${BOLD}cat ~/Downloads/*.pem${NC}"
    echo -e "   • Copy toàn bộ nội dung (kể cả dòng -----BEGIN/END-----)"
    echo ""
    echo -e "${CYAN}Trên Windows:${NC}"
    echo -e "   • Mở file .pem bằng Notepad"
    echo -e "   • Copy toàn bộ nội dung"
    echo ""
    echo -e "${CYAN}Trên Linux:${NC}"
    echo -e "   • Mở Terminal, chạy: ${BOLD}cat ~/Downloads/*.pem${NC}"
    echo -e "   • Copy toàn bộ nội dung"
    echo ""
    read -rp "   Nhấn Enter để mở editor paste private key..." DUMMY
    
    cat > "$OCI_KEY" << 'TEMPLATE'
# Paste private key vào đây (xoá toàn bộ dòng comment này)
# Phải có cả dòng -----BEGIN PRIVATE KEY----- và -----END PRIVATE KEY-----
# Sau khi paste: Ctrl+O → Enter → Ctrl+X
TEMPLATE
    nano "$OCI_KEY"
    
    # Xoá comment lines
    grep -v "^#" "$OCI_KEY" > "$OCI_KEY.tmp"
    mv "$OCI_KEY.tmp" "$OCI_KEY"
    chmod 600 "$OCI_KEY"
    
    if ! grep -q "BEGIN" "$OCI_KEY"; then
        echo -e "${RED}❌ Private key không hợp lệ. Phải có -----BEGIN PRIVATE KEY-----${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ Private key đã lưu${NC}"
fi

# ─── Đọc thông tin ────────────────────────────────────────
OCI_USER=$(grep "^user=" "$OCI_CONFIG" | cut -d= -f2- | tr -d ' \r\n')
OCI_TENANCY=$(grep "^tenancy=" "$OCI_CONFIG" | cut -d= -f2- | tr -d ' \r\n')
OCI_FINGERPRINT=$(grep "^fingerprint=" "$OCI_CONFIG" | cut -d= -f2- | tr -d ' \r\n')
OCI_REGION=$(grep "^region=" "$OCI_CONFIG" | cut -d= -f2- | tr -d ' \r\n')

echo ""
echo -e "${CYAN}📌 Thông tin account:${NC}"
echo -e "   User    : ${OCI_USER:0:50}${OCI_USER:50:20}"
echo -e "   Tenancy : ${OCI_TENANCY:0:50}${OCI_TENANCY:50:20}"
echo -e "   Region  : $OCI_REGION"
echo -e "   Key     : $OCI_FINGERPRINT"

# ─── Test kết nối ─────────────────────────────────────────
echo ""
echo -e "${YELLOW}🔍 Kiểm tra kết nối Oracle...${NC}"
TEST_OUT=$(~/bin/oci iam region list 2>&1)
if echo "$TEST_OUT" | grep -q "ERROR\|malformed\|InvalidParameter"; then
    echo -e "${RED}❌ Không kết nối được Oracle:${NC}"
    echo "$TEST_OUT" | head -10
    echo ""
    echo -e "${YELLOW}Khắc phục:${NC}"
    echo -e "   rm ~/.oci/config ~/.oci/oci_api_key.pem"
    echo -e "   ./oracle-sniper-setup.sh"
    exit 1
fi
echo -e "${GREEN}✅ Kết nối Oracle OK${NC}"

# ─── Lấy Subnet ID ────────────────────────────────────────
echo ""
echo -e "${YELLOW}🔍 Lấy danh sách Subnets...${NC}"
SUBNETS=$(~/bin/oci network subnet list --compartment-id "$OCI_TENANCY" --region "$OCI_REGION" 2>/dev/null)
SUBNET_COUNT=$(echo "$SUBNETS" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('data',[])))" 2>/dev/null || echo "0")

if [ "$SUBNET_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}⚠️  Chưa có subnet. Tạo VCN trước trên Oracle Console:${NC}"
    echo -e "   👉 Networking → Virtual Cloud Networks → Start VCN Wizard"
    read -rp "   Hoặc nhập Subnet OCID thủ công: " OCI_SUBNET_ID
else
    echo ""
    echo -e "${BOLD}📋 Chọn Subnet:${NC}"
    echo "$SUBNETS" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for i,s in enumerate(d.get('data',[])):
    print(f\"  [{i+1}] {s.get('display-name','?')} | {s.get('cidr-block','?')}\")
"
    read -rp "   Chọn số [1-$SUBNET_COUNT] (Enter=1): " SUBNET_CHOICE
    SUBNET_CHOICE=${SUBNET_CHOICE:-1}
    SUBNET_CHOICE=$((SUBNET_CHOICE - 1))
    OCI_SUBNET_ID=$(echo "$SUBNETS" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['data'][$SUBNET_CHOICE]['id'])")
    echo -e "${GREEN}✅ Subnet OK${NC}"
fi

# ─── Lấy Image ID ─────────────────────────────────────────
echo ""
echo -e "${YELLOW}🔍 Tìm Ubuntu ARM images...${NC}"
IMAGES=$(~/bin/oci compute image list --compartment-id "$OCI_TENANCY" --region "$OCI_REGION" --shape "VM.Standard.A1.Flex" --operating-system "Canonical Ubuntu" --sort-by TIMECREATED --sort-order DESC 2>/dev/null)
IMAGE_COUNT=$(echo "$IMAGES" | python3 -c "import json,sys; d=json.load(sys.stdin); print(min(5,len(d.get('data',[]))))" 2>/dev/null || echo "0")

if [ "$IMAGE_COUNT" -eq 0 ]; then
    read -rp "   Nhập Image OCID thủ công: " OCI_IMAGE_ID
else
    echo ""
    echo -e "${BOLD}📋 Chọn Ubuntu Image (ARM):${NC}"
    echo "$IMAGES" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for i,img in enumerate(d.get('data',[])[:5]):
    print(f\"  [{i+1}] {img.get('display-name','?')} ({img.get('time-created','?')[:10]})\")
"
    read -rp "   Chọn [1-$IMAGE_COUNT] (Enter=1, mới nhất): " IMAGE_CHOICE
    IMAGE_CHOICE=${IMAGE_CHOICE:-1}
    IMAGE_CHOICE=$((IMAGE_CHOICE - 1))
    OCI_IMAGE_ID=$(echo "$IMAGES" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['data'][$IMAGE_CHOICE]['id'])")
    echo -e "${GREEN}✅ Image OK${NC}"
fi

# ─── Chọn CPU và RAM ─────────────────────────────────────
echo ""
echo -e "${BOLD}⚙️  Cấu hình instance (free tier tối đa: 4 OCPU / 24GB):${NC}"
echo "   [1] 1 OCPU  [2] 2 OCPU  [3] 3 OCPU  [4] 4 OCPU"
read -rp "   OCPU [1-4] (Enter=4): " CPU_CHOICE
case $CPU_CHOICE in
    1) OCI_OCPUS=1 ;; 2) OCI_OCPUS=2 ;; 3) OCI_OCPUS=3 ;; *) OCI_OCPUS=4 ;;
esac

echo "   [1] 6GB  [2] 12GB  [3] 16GB  [4] 24GB"
read -rp "   RAM [1-4] (Enter=4): " RAM_CHOICE
case $RAM_CHOICE in
    1) OCI_MEMORY_IN_GBS=6 ;; 2) OCI_MEMORY_IN_GBS=12 ;; 3) OCI_MEMORY_IN_GBS=16 ;; *) OCI_MEMORY_IN_GBS=24 ;;
esac
echo -e "${GREEN}✅ ${OCI_OCPUS} OCPU / ${OCI_MEMORY_IN_GBS}GB RAM${NC}"

# ─── SSH key ──────────────────────────────────────────────
echo ""
if [ -f ~/.ssh/id_rsa.pub ]; then
    OCI_SSH_PUBLIC_KEY=$(cat ~/.ssh/id_rsa.pub)
elif [ -f ~/.ssh/id_ed25519.pub ]; then
    OCI_SSH_PUBLIC_KEY=$(cat ~/.ssh/id_ed25519.pub)
else
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N "" -q
    OCI_SSH_PUBLIC_KEY=$(cat ~/.ssh/id_rsa.pub)
fi
echo -e "${GREEN}✅ SSH key sẵn sàng${NC}"

# ─── GitHub CLI ───────────────────────────────────────────
if ! command -v gh &>/dev/null; then
    echo -e "${YELLOW}📦 Cài GitHub CLI...${NC}"
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    sudo apt update -qq && sudo apt install -y gh
fi

if ! gh auth status &>/dev/null; then
    echo ""
    echo -e "${BOLD}🔑 Đăng nhập GitHub:${NC}"
    echo -e "   1. Mở: ${BOLD}https://github.com/settings/tokens/new${NC}"
    echo -e "   2. Note: oracle-sniper, Expiration: No expiration"
    echo -e "   3. Tick: ${BOLD}repo${NC} và ${BOLD}workflow${NC}"
    echo -e "   4. Click ${BOLD}Generate token${NC}, copy token"
    echo ""
    read -rsp "   Paste GitHub token: " GH_TOKEN
    echo ""
    echo "$GH_TOKEN" | gh auth login --with-token
fi
echo -e "${GREEN}✅ GitHub OK${NC}"

# ─── Confirm ──────────────────────────────────────────────
echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  Region: $OCI_REGION  |  $OCI_OCPUS OCPU  |  ${OCI_MEMORY_IN_GBS}GB RAM${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════╝${NC}"
read -rp "   Push secrets lên GitHub? [Y/n]: " CONFIRM
[[ "$CONFIRM" == "n" || "$CONFIRM" == "N" ]] && echo "Đã hủy." && exit 0

# ─── Set secrets ──────────────────────────────────────────
echo ""
echo -e "${YELLOW}⬆️  Đẩy secrets lên GitHub...${NC}"
set_secret() {
    echo -n "   $1... "
    printf '%s' "$2" | gh secret set "$1" --repo "$GITHUB_REPO"
    echo -e "${GREEN}✓${NC}"
}
set_secret "OCI_USER_ID"         "$OCI_USER"
set_secret "OCI_TENANCY_ID"      "$OCI_TENANCY"
set_secret "OCI_KEY_FINGERPRINT" "$OCI_FINGERPRINT"
set_secret "OCI_REGION"          "$OCI_REGION"
set_secret "OCI_SUBNET_ID"       "$OCI_SUBNET_ID"
set_secret "OCI_IMAGE_ID"        "$OCI_IMAGE_ID"
set_secret "OCI_SSH_PUBLIC_KEY"  "$OCI_SSH_PUBLIC_KEY"
set_secret "OCI_PRIVATE_KEY"     "$(cat "$OCI_KEY")"
set_secret "OCI_OCPUS"           "$OCI_OCPUS"
set_secret "OCI_MEMORY_IN_GBS"   "$OCI_MEMORY_IN_GBS"
set_secret "OCI_SHAPE"           "VM.Standard.A1.Flex"
set_secret "OCI_MAX_INSTANCES"   "1"
set_secret "OCI_AVAILABILITY_DOMAIN" ""

gh workflow enable oci.yml --repo "$GITHUB_REPO" 2>/dev/null || true
gh workflow run oci.yml --repo "$GITHUB_REPO" 2>/dev/null || true

echo ""
echo -e "${BOLD}${GREEN}╔════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║ ✅ XONG! Workflow snipe ARM mỗi 5 phút       ║${NC}"
echo -e "${BOLD}${GREEN}╚════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "   Theo dõi: ${BOLD}https://github.com/${GITHUB_REPO}/actions${NC}"
echo ""
echo -e "${YELLOW}💡 Lần sau dùng account khác:${NC}"
echo -e "   rm ~/.oci/config ~/.oci/oci_api_key.pem"
echo -e "   ./oracle-sniper-setup.sh"
