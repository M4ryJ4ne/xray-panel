import asyncio
import html
import subprocess
from telegram import Update, ReplyKeyboardMarkup
import os
from telegram.ext import ApplicationBuilder, CommandHandler, MessageHandler, ContextTypes, filters


# =========================
# ЗАГРУЗКА КОНФИГА
# =========================

config = {}

with open("config") as f:
    for line in f:
        line = line.strip()
        if not line or "=" not in line:
            continue
        key, value = line.split("=", 1)
        config[key.strip()] = value.strip().strip('"')

TOKEN = config["BOT_TOKEN"]
#ADMIN_ID = int(config["ADMIN_ID"])
SCRIPTS_DIR = config["SCRIPTS_DIR"]
REBOOT_PASS = config["REBOOT_PASS"]
BOT_PASS = config["BOT_PASS"]

AUTH_DB = "/root/xray-panel/bot_db/auth_users.db"
os.makedirs("/root/xray-panel/bot_db", exist_ok=True)
if not os.path.exists(AUTH_DB):
    open(AUTH_DB, "a").close()


# =========================
# КНОПКИ МЕНЮ
# =========================

keyboard = [

    ["Мониторинг ☣️", "Статистика ☢️"],
    ["Профили ✳️", "Устройства 🆔"],
    ["Добавить Профиль ⚛️", "Удалить Профиль ❎"],
    ["Перезапустить Сервер 📴"]

]

reply_markup = ReplyKeyboardMarkup(keyboard, resize_keyboard=True)


# =========================
# /start
# =========================

async def start(update, context):

    user_id = update.message.from_user.id

    if is_authorized(user_id):
        await update.message.reply_text(
            "🪁  XRAY PANEL 🪁 ",
            reply_markup=reply_markup
        )
        return

    context.user_data["action"] = "bot_auth"

    await update.message.reply_text("Требуется ключ 🫆")


# =========================
# АВТОРИЗАЦИЯ ПО БАЗЕ USER ID
# =========================

def is_authorized(user_id: int) -> bool:
    with open(AUTH_DB, "r") as f:
        ids = {line.strip() for line in f if line.strip()}
    return str(user_id) in ids

def add_authorized_user(user_id: int) -> None:
    if is_authorized(user_id):
        return
    with open(AUTH_DB, "a") as f:
        f.write(f"{user_id}\n")


# =========================
# LIVE MONITOR TASK
# =========================

async def live_monitor_task(update, context):

    chat_id = update.effective_chat.id

    while context.user_data.get("live_profile_running", False):

        result = subprocess.run(
            [f"{SCRIPTS_DIR}/live_profile.sh", "2"],
            capture_output=True,
            text=True
        )

        output = (result.stdout + result.stderr).strip()

        lines = output.splitlines()
        formatted = ""

        for line in lines:

            stripped = line.strip()

            # профиль
            if stripped.startswith(tuple(str(i) for i in range(1, 100))) and "." in stripped:

                parts = stripped.split(" ", 1)

                if len(parts) == 2 and not parts[1].count(".") == 3:
                    number = parts[0]
                    profile = parts[1]

                    formatted += f"{number} <code>{html.escape(profile)}</code>\n"
                    continue

            # IP
            parts = stripped.split()

            if len(parts) == 2 and parts[1].count(".") == 3:

                number = parts[0]
                ip = parts[1]

                formatted += f"   {number} <code>{ip}</code>\n"
                continue

            formatted += html.escape(line) + "\n"

        old_msg_id = context.user_data.get("live_profile_message_id")
        if old_msg_id:
            try:
                await context.bot.delete_message(
                    chat_id=chat_id,
                    message_id=old_msg_id
                )
            except:
                pass

        sent = await context.bot.send_message(
            chat_id=chat_id,
            text=formatted,
            parse_mode="HTML"
        )

        context.user_data["live_profile_message_id"] = sent.message_id

        await asyncio.sleep(2)

    # сброс флага задачи
    context.user_data["live_monitor_task"] = None


# =========================
# ОБРАБОТКА КНОПОК
# =========================

async def handle_message(update, context):

    text = update.message.text

    user_id = update.message.from_user.id
    action = context.user_data.get("action")

    # -------------------------
    # ВВОД ПАРОЛЯ ДЛЯ ДОСТУПА К БОТУ
    # -------------------------

    if action == "bot_auth":

        password = text.strip()

        if password != BOT_PASS:
            await update.message.reply_text("Ключ неверный 🫟")
            return

        add_authorized_user(user_id)
        context.user_data["action"] = None

        await update.message.reply_text(
            "Доступ разрешён ✅",
            reply_markup=reply_markup
        )

        return

    # если пользователь не авторизован — ничего не даём делать
    if not is_authorized(user_id):
        context.user_data["action"] = "bot_auth"
        await update.message.reply_text("Требуется ключ 🫆")
        return


    # -------------------------
    # ОСТАНОВКА LIVE MONITOR
    # если нажата любая другая кнопка
    # -------------------------

    if text != "Мониторинг ☣️":
        context.user_data["live_profile_running"] = False


    # =========================
    # БЛОК НОВЫХ КНОПОК
    # =========================
    # сюда вставляется новая команда


    if text == "Test":

        result = subprocess.run(
            [f"{SCRIPTS_DIR}/test_button.sh"],
            capture_output=True,
            text=True
        )

        await update.message.reply_text(result.stdout)


    # -------------------------
    # PROFILE REPORT
    # -------------------------

    if text == "Статистика ☢️":

        result = subprocess.run(
            [f"{SCRIPTS_DIR}/profile_report.sh"],
            capture_output=True,
            text=True
        )

        output = result.stdout + result.stderr
        lines = output.splitlines()

        formatted = ""

        for line in lines:

            stripped = line.strip()

            # профиль
            if stripped and stripped[0].isdigit() and ". " in stripped and not stripped.startswith("Traffic"):
                parts = stripped.split(" ", 1)

                if len(parts) == 2:
                    number = parts[0]
                    value = parts[1]

                    # если это IP
                    if value.count(".") == 3 and all(part.isdigit() for part in value.split(".")):
                        formatted += f"   {number} <code>{html.escape(value)}</code>\n"
                        continue

                    # если это профиль
                    if not value.startswith("Traffic") and not value.startswith("Devices") and not value.startswith("first"):
                        formatted += f"{number} <code>{html.escape(value)}</code>\n"
                        continue

            formatted += html.escape(line) + "\n"

        await update.message.reply_text(
            formatted,
            parse_mode="HTML"
        )

        return


    # -------------------------
    # USER LIST
    # -------------------------

    if text == "Профили ✳️":

        result = subprocess.run(
            [f"{SCRIPTS_DIR}/list_users.sh"],
            capture_output=True,
            text=True
        )

        output = result.stdout
        lines = output.splitlines()

        formatted = ""

        for line in lines:

            stripped = line.strip()

            # ссылка подключения
            if stripped.startswith("vless://"):
                formatted += f"<code>{html.escape(stripped)}</code>\n"
                continue

            # профиль вида "1. MaryJane"
            if stripped and stripped[0].isdigit() and ". " in stripped:
                left, right = stripped.split(". ", 1)
                formatted += f"{html.escape(left)}. <code>{html.escape(right)}</code>\n"
                continue

            formatted += html.escape(line) + "\n"

        await update.message.reply_text(
            formatted,
            parse_mode="HTML"
        )

    # -------------------------
    # ADD USER
    # -------------------------

    if text == "Добавить Профиль ⚛️":

        await update.message.reply_text(
            "Введите имя нового профиля 🙋‍♂"
        )

        context.user_data["action"] = "add_user"

        return


    # -------------------------
    # REMOVE USER
    # -------------------------

    if text == "Удалить Профиль ❎":

        result = subprocess.run(
            [f"{SCRIPTS_DIR}/list_users.sh"],
            capture_output=True,
            text=True
        )

        output = result.stdout
        lines = output.splitlines()

        formatted = ""

        for line in lines:

            stripped = line.strip()

            # ссылка подключения
            if stripped.startswith("vless://"):
                formatted += f"<code>{html.escape(stripped)}</code>\n"
                continue

            # профиль вида "1. MaryJane"
            if stripped and stripped[0].isdigit() and ". " in stripped:
                left, right = stripped.split(". ", 1)
                formatted += f"{html.escape(left)}. <code>{html.escape(right)}</code>\n"
                continue

            formatted += html.escape(line) + "\n"

        formatted += "\nВведите номер профиля 🙅‍♂"

        await update.message.reply_text(
            formatted,
            parse_mode="HTML"
        )

        context.user_data["action"] = "remove_user"

        return


    # -------------------------
    # LIVE MONITOR
    # -------------------------

    if text == "Мониторинг ☣️":

        # если монитор уже работает — ничего не делаем
        if context.user_data.get("live_monitor_task"):
            await update.message.reply_text("Нажми другую кнопку чтобы отключить ⚠️")
            return

        context.user_data["live_profile_running"] = True

        old_msg_id = context.user_data.get("live_profile_message_id")
        if old_msg_id:
            try:
                await context.bot.delete_message(
                    chat_id=update.effective_chat.id,
                    message_id=old_msg_id
                )
            except:
                pass

        task = asyncio.create_task(live_monitor_task(update, context))

        context.user_data["live_monitor_task"] = task

        return


    # -------------------------
    # REBOOT SERVER
    # -------------------------

    if text == "Перезапустить Сервер 📴":

        await update.message.reply_text(
            "Требуется ключ 🫆"
        )

        context.user_data["action"] = "reboot_server"

        return


    # -------------------------
    # DEVICES LIST
    # -------------------------

    if text == "Устройства 🆔":

        result = subprocess.run(
            [f"{SCRIPTS_DIR}/list_devices.sh"],
            capture_output=True,
            text=True
        )

        output = result.stdout
        lines = output.splitlines()

        formatted = ""

        for line in lines:

            stripped = line.strip()

            # строки вида "1. MaryJane" или "1. 185.108.19.37"
            if stripped and stripped[0].isdigit() and ". " in stripped:

                left, right = stripped.split(". ", 1)

                # IP
                if right.count(".") == 3:
                    formatted += f"   {html.escape(left)}. <code>{html.escape(right)}</code>\n"
                else:
                    formatted += f"{html.escape(left)}. <code>{html.escape(right)}</code>\n"

                continue

            formatted += html.escape(line) + "\n"

        await update.message.reply_text(
            formatted,
            parse_mode="HTML"
        )

        return


    # -------------------------
    # ВВОД ИМЕНИ ДЛЯ ADD USER
    # -------------------------

    if action == "add_user":

        username = text

        result = subprocess.run(
            [f"{SCRIPTS_DIR}/add_user.sh", username],
            capture_output=True,
            text=True
        )

        output = result.stdout
        lines = output.splitlines()

        formatted = ""
        link = ""

        for line in lines:

            if line.startswith("vless://"):
                link = line
            else:
                formatted += line + "\n"

        await update.message.reply_text(
            f"{formatted}\n`{link}`",
            parse_mode="Markdown"
        )

        context.user_data["action"] = None

        return


    # -------------------------
    # ВВОД НОМЕРА ДЛЯ REMOVE USER
    # -------------------------

    if action == "remove_user":

        number = text

        result = subprocess.run(
            [f"{SCRIPTS_DIR}/del_user.sh"],
            input=number + "\n",
            text=True,
            capture_output=True
        )

        output = result.stdout + result.stderr

        await update.message.reply_text(
            output
        )

        context.user_data["action"] = None

        return


    # -------------------------
    # ВВОД ПАРОЛЯ ДЛЯ REBOOT SERVER
    # -------------------------

    if action == "reboot_server":

        password = text.strip()

        if password != REBOOT_PASS:
            await update.message.reply_text("Ключ неверный 🫟")
            context.user_data["action"] = None
            return

        result = subprocess.run(
            [f"{SCRIPTS_DIR}/reboot.sh"],
            capture_output=True,
            text=True
        )

        output = (result.stdout + result.stderr).strip()

        await update.message.reply_text(
            output if output else "Отправлен в ребут ♻️"
        )

        context.user_data["action"] = None

        return


# =========================
# ЗАПУСК БОТА
# =========================

app = ApplicationBuilder().token(TOKEN).build()

app.add_handler(CommandHandler("start", start))
app.add_handler(MessageHandler(filters.TEXT, handle_message))

app.run_polling()
