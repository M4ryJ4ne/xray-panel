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

    ["Add User", "Remove User"],

    ["User List"],

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


# =========================
# ЗАПУСК БОТА
# =========================

app = ApplicationBuilder().token(TOKEN).build()

app.add_handler(CommandHandler("start", start))
app.add_handler(MessageHandler(filters.TEXT, handle_message))

app.run_polling()
