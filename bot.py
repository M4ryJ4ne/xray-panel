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
        key, value = line.strip().split("=")
        config[key] = value

TOKEN = config["BOT_TOKEN"]
ADMIN_ID = int(config["ADMIN_ID"])
SCRIPTS_DIR = config["SCRIPTS_DIR"]


# =========================
# КНОПКИ МЕНЮ
# =========================

keyboard = [

    ["User List"],

    ["Add User", "Remove User"],

    # =========================
    # БЛОК ДОБАВЛЕНИЯ КНОПОК
    # =========================
    # сюда добавляется новая кнопка

    ["Test"]

]

reply_markup = ReplyKeyboardMarkup(keyboard, resize_keyboard=True)


# =========================
# /start
# =========================

async def start(update, context):

    if update.message.from_user.id != ADMIN_ID:
        await update.message.reply_text("Access denied")
        return

    await update.message.reply_text(
        "XRAY PANEL",
        reply_markup=reply_markup
    )


# =========================
# ОБРАБОТКА КНОПОК
# =========================

async def handle_message(update, context):

    text = update.message.text


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
    # ВВОД ИМЕНИ ДЛЯ ADD USER
    # -------------------------

    action = context.user_data.get("action")

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



# =========================
# ЗАПУСК БОТА
# =========================

app = ApplicationBuilder().token(TOKEN).build()

app.add_handler(CommandHandler("start", start))
app.add_handler(MessageHandler(filters.TEXT, handle_message))

app.run_polling()
