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

    ["Live Monitor"],

    ["User List", "Devices"],
    ["Add User", "Remove User"],
    ["Reboot Server"]

]

reply_markup = ReplyKeyboardMarkup(keyboard, resize_keyboard=True)


# =========================
# /start
# =========================

async def start(update, context):

    user_id = update.message.from_user.id

    if is_authorized(user_id):
        await update.message.reply_text(
            "XRAY PANEL",
            reply_markup=reply_markup
        )
        return

    context.user_data["action"] = "bot_auth"

    await update.message.reply_text("Введите пароль от бота:")


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
            text=f"<pre>{html.escape(output)}</pre>",
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
            await update.message.reply_text("Неверный пароль")
            return

        add_authorized_user(user_id)
        context.user_data["action"] = None

        await update.message.reply_text(
            "Доступ разрешён",
            reply_markup=reply_markup
        )

        return

    # если пользователь не авторизован — ничего не даём делать
    if not is_authorized(user_id):
        context.user_data["action"] = "bot_auth"
        await update.message.reply_text("Введите пароль от бота:")
        return


    # -------------------------
    # ОСТАНОВКА LIVE MONITOR
    # если нажата любая другая кнопка
    # -------------------------

    if text != "Live Monitor":
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
    # USER LIST
    # -------------------------

    if text == "User List":

        result = subprocess.run(
            [f"{SCRIPTS_DIR}/list_users.sh"],
            capture_output=True,
            text=True
        )

        output = result.stdout
        lines = output.splitlines()

        formatted = ""

        for line in lines:

            # если это ссылка vless
            if line.startswith("vless://"):

                # делаем форматирование чтобы копировалось
                formatted += f"`{line}`\n"

            else:
                # обычный текст без форматирования
                formatted += line + "\n"

        await update.message.reply_text(
            formatted,
            parse_mode="Markdown"
        )


    # -------------------------
    # ADD USER
    # -------------------------

    if text == "Add User":

        await update.message.reply_text(
            "Введите имя пользователя:"
        )

        context.user_data["action"] = "add_user"

        return


    # -------------------------
    # REMOVE USER
    # -------------------------

    if text == "Remove User":

        result = subprocess.run(
            [f"{SCRIPTS_DIR}/list_users.sh"],
            capture_output=True,
            text=True
        )

        output = result.stdout
        lines = output.splitlines()

        formatted = ""

        for line in lines:

            if line.startswith("vless://"):
                formatted += f"`{line}`\n"
            else:
                formatted += line + "\n"

        formatted += "\nВведите номер пользователя для удаления:"

        await update.message.reply_text(
            formatted,
            parse_mode="Markdown"
        )

        context.user_data["action"] = "remove_user"

        return


    # -------------------------
    # LIVE MONITOR
    # -------------------------

    if text == "Live Monitor":

        # если монитор уже работает — ничего не делаем
        if context.user_data.get("live_monitor_task"):
            await update.message.reply_text("Live monitor уже запущен")
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

    if text == "Reboot Server":

        await update.message.reply_text(
            "Введите пароль для перезапуска сервера:"
        )

        context.user_data["action"] = "reboot_server"

        return


    # -------------------------
    # DEVICES LIST
    # -------------------------

    if text == "Devices":

        result = subprocess.run(
            [f"{SCRIPTS_DIR}/list_devices.sh"],
            capture_output=True,
            text=True
        )

        output = result.stdout + result.stderr

        await update.message.reply_text(
            f"<pre>{html.escape(output)}</pre>",
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
            await update.message.reply_text("Неверный пароль")
            context.user_data["action"] = None
            return

        result = subprocess.run(
            [f"{SCRIPTS_DIR}/reboot.sh"],
            capture_output=True,
            text=True
        )

        output = (result.stdout + result.stderr).strip()

        await update.message.reply_text(
            output if output else "Сервер перезагружается..."
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
