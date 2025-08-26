# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

# 打印带颜色的消息
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_header() { echo -e "${CYAN}${BOLD}$1${NC}"; }
print_menu() { echo -e "${PURPLE}$1${NC}"; }
print_dim() { echo -e "${DIM}$1${NC}"; }

# 日志函数别名
info() { print_info "$1"; }
success() { print_success "$1"; }
error() { print_error "$1"; }
warn() { print_warning "$1"; }
warning() { print_warning "$1"; }
header() { print_header "$1"; }
highlight() { echo -e "${PURPLE}$1${NC}"; }
