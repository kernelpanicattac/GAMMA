#!/bin/bash

# Функция подтверждения продолжения
prompt_continue() {
  while true; do
    read -p "$1 (y/n): " yn
    case $yn in
      [Yy]*) return 0 ;;
      [Nn]*) return 1 ;;
      *) echo "Пожалуйста, введите 'y' или 'n'." ;;
    esac
  done
}

# Определение ОС для установки пакетов
OS_TYPE=""
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS_TYPE=$ID
fi

install_packages() {
  case "$OS_TYPE" in
    ubuntu|debian)
      sudo apt-get update
      sudo apt-get install -y unzip unrar libunrar zip python3-venv python3-pip git || return 1
      ;;
    arch|manjaro)
      sudo pacman -Sy --noconfirm unzip unrar p7zip python-virtualenv python-pip git || return 1
      ;;
    nobara)
      sudo dnf install -y unzip unrar libunrar zip python3-venv python3-pip git || return 1
      ;;
    *)
      echo "Неизвестная ОС: $OS_TYPE. Установите вручную unzip, unrar, libunrar, zip, python3-venv, python3-pip, git"
      return 1
      ;;
  esac
  return 0
}

setup_gamma_launcher() {
  source ./gamma-launcher/venv/bin/activate
  if command -v gamma-launcher >/dev/null 2>&1; then
    if gamma-launcher --version >/dev/null 2>&1; then
      echo "Gamma-launcher уже установлен и работает. Пропускаем установку."
      return 0
    fi
  fi
  echo "Устанавливаем gamma-launcher..."
  pip install --upgrade pip
  pip install ./gamma-launcher
  if [ $? -ne 0 ]; then
    echo "Ошибка при установке gamma-launcher."
    return 1
  fi
  return 0
}

backup_user_data() {
  echo "------- Создаем директорию для резервной копии..."
  dir_name="saves_backup_$(date +%F)_$(date +%H_%M)"
  mkdir -pv "$dir_name/Anomaly/appdata" "$dir_name/GAMMA/mods"

  echo "------- Резервное копирование user.ltx (бинды и настройки)..."
  cp -v ./Anomaly/appdata/user.ltx "$dir_name/Anomaly/appdata/"

  echo "------- Резервное копирование сохранений..."
  cp -R -v ./Anomaly/appdata/savedgames "$dir_name/Anomaly/appdata/"

  echo "------- Резервное копирование MCM значений..."
  cp -R -v "./GAMMA/mods/G.A.M.M.A. MCM values - Rename to keep your personal changes" "$dir_name/GAMMA/mods/"

  echo "Резервная копия создана в $dir_name"
}

create_update_script() {
  cat > "$1/update_gamma.sh" << 'EOF'
#!/bin/bash
DE=${XDG_CURRENT_DESKTOP,,}

backup_user_data() {
  echo "------- Создаем директорию для резервной копии..."
  dir_name="saves_backup_$(date +%F)_$(date +%H_%M)"
  mkdir -pv "$dir_name/Anomaly/appdata" "$dir_name/GAMMA/mods"

  echo "------- Резервное копирование user.ltx (бинды и настройки)..."
  cp -v ./Anomaly/appdata/user.ltx "$dir_name/Anomaly/appdata/"

  echo "------- Резервное копирование сохранений..."
  cp -R -v ./Anomaly/appdata/savedgames "$dir_name/Anomaly/appdata/"

  echo "------- Резервное копирование MCM значений..."
  cp -R -v "./GAMMA/mods/G.A.M.M.A. MCM values - Rename to keep your personal changes" "$dir_name/GAMMA/mods/"

  echo "Резервная копия создана в $dir_name"
}

ask_update() {
  case "$DE" in
    kde*)
      kdialog --yesno "Обновить GAMMA?"
      return $? ;;
    gnome*|unity*|xfce*)
      zenity --question --text="Обновить GAMMA?"
      return $? ;;
    *)
      read -p "Обновить GAMMA? (y/n): " ans
      [[ $ans =~ ^[Yy]$ ]] && return 0 || return 1 ;;
  esac
}

ask_update
if [ $? -eq 0 ]; then
  # Переход в директорию, где лежит скрипт
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  cd "$SCRIPT_DIR" || { echo "Ошибка: не удалось перейти в $SCRIPT_DIR"; read; exit 1; }

  source ./gamma-launcher/venv/bin/activate || { echo "Ошибка: не удалось активировать окружение"; read; exit 1; }

  backup_user_data

  rm -rf ./Anomaly ./GAMMA
  mkdir ./Anomaly ./GAMMA
  gamma-launcher full-install --anomaly ./Anomaly --gamma ./GAMMA --cache-directory ./cache
  echo "Обновление завершено"; read
fi
EOF
  chmod +x "$1/update_gamma.sh"
  echo "Скрипт update_gamma.sh создан в $1"
}

create_desktop_entry() {
  local desktop_file_path="$HOME/.local/share/applications/GAMMA_GUI_Installer.desktop"
  local icon_path="$1/update.png"
  local script_path="$1/update_gamma.sh"
  local exec_cmd="sh -c '$script_path; echo \"Нажмите Enter для выхода...\"; read'"

  cat > "$desktop_file_path" << EOF
[Desktop Entry]
Type=Application
Name=GAMMA GUI Installer
Comment=Установщик GAMMA
Icon=$icon_path
Exec=$exec_cmd
Terminal=true
Categories=Game;
StartupNotify=true
EOF

  echo "Ярлык создан: $desktop_file_path"
}

if ! install_packages; then
  echo "Ошибка при установке пакетов. Установите необходимые пакеты вручную."
  if prompt_continue "Продолжить выполнение скрипта без установки пакетов?"; then
    echo "Пропускаем установку пакетов. Продолжаем..."
  else
    echo "Выход из скрипта."
    exit 1
  fi
fi

if [ -z "$1" ]; then
  echo "Ошибка: Не указан путь установки."
  echo "Использование: $0 /путь/к/папке"
  exit 1
fi

WORKDIR="$1"

mkdir -p "$WORKDIR"
cd "$WORKDIR" || { echo "Не удалось перейти в директорию $WORKDIR"; exit 1; }

if [ ! -d "gamma-launcher" ]; then
  git clone https://github.com/Mord3rca/gamma-launcher.git
fi

if [ ! -d "gamma-launcher/venv" ]; then
  python3 -m venv ./gamma-launcher/venv
fi

setup_gamma_launcher
if [ $? -ne 0 ]; then
  echo "Не удалось установить gamma-launcher, продолжение невозможно."
  exit 1
fi

backup_user_data

echo "------- Удаляем старые папки Anomaly и GAMMA для чистого обновления..."
rm -rf ./Anomaly ./GAMMA
mkdir ./Anomaly ./GAMMA

gamma-launcher full-install --anomaly ./Anomaly --gamma ./GAMMA --cache-directory ./cache

create_update_script "$WORKDIR"
create_desktop_entry "$WORKDIR"

deactivate
