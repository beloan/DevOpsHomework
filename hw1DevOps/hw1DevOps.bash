#!/bin/bash

LOG_FILE="script.log"
TARGET_DIR=""


log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

if [[ $EUID -ne 0 ]]; then
    log "Ошибка: Скрипт должен быть запущен с правами root."
    exit 1
fi


while getopts ":d:" opt; do
    case $opt in
        d)
            TARGET_DIR="$OPTARG"
            ;;
        \?)
            log "Неверный ключ: -$OPTARG"
            exit 1
            ;;
        :)
            log "Ключ -$OPTARG требует путь к директории."
            exit 1
            ;;
    esac
done


if [[ -z "$TARGET_DIR" ]]; then
    read -p "Введите путь для создания рабочих директорий: " TARGET_DIR
fi

if [[ ! -d "$TARGET_DIR" ]]; then
    log "Создание директории $TARGET_DIR..."
    mkdir -p "$TARGET_DIR" || {
        log "Ошибка: Не удалось создать директорию $TARGET_DIR."
        exit 1
    }
fi


if ! grep -q "^dev:" /etc/group; then
    log "Создание группы dev..."
    groupadd dev || {
        log "Ошибка: Не удалось создать группу dev."
        exit 1
    }
else
    log "Группа dev уже существует."
fi

log "Добавление несистемных пользователей в группу dev..."
while IFS=: read -r username _ uid _ _ home _; do
    if [[ "$uid" -ge 1000 && "$home" == /home/* ]]; then
        usermod -aG dev "$username" && log "Пользователь $username добавлен в группу dev."
    fi
done < /etc/passwd

SUDOERS_ENTRY="%dev ALL=(ALL) NOPASSWD:ALL"
if ! grep -q "$SUDOERS_ENTRY" /etc/sudoers; then
    log "Настройка sudo для группы dev..."
    echo "$SUDOERS_ENTRY" >> /etc/sudoers || {
        log "Ошибка: Не удалось настроить sudo для группы dev."
        exit 1
    }
else
    log "Права sudo для группы dev уже настроены."
fi

log "Создание рабочих директорий в $TARGET_DIR..."
while IFS=: read -r username _ uid _ _ home _; do
    if [[ "$uid" -ge 1000 && "$home" == /home/* ]]; then
        WORKDIR="${TARGET_DIR}/${username}_workdir"
        if [[ ! -d "$WORKDIR" ]]; then
            mkdir -p "$WORKDIR" && log "Директория $WORKDIR создана."
            chown "$username:$(id -gn "$username")" "$WORKDIR" && log "Назначены владелец и группа для $WORKDIR."
            chmod 660 "$WORKDIR" && log "Установлены права 660 для $WORKDIR."
            setfacl -m g:dev:r-x "$WORKDIR" && log "Добавлены права на чтение для группы dev."
        else
            log "Директория $WORKDIR уже существует."
        fi
    fi
done < /etc/passwd

log "Скрипт успешно завершен."
exit 0