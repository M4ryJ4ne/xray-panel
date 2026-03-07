import asyncio
import html
import subprocess
from telegram import Update, ReplyKeyboardMarkup
from telegram.ext import ApplicationBuilder, CommandHandler, MessageHandler, ContextTypes, filters

TOKEN = "8695185044:AAFqcgnGed63vrtKUhmEyQQH0QQrxHqaIpE"
PASSWORD = "LsCjMHMJM@MSMDM@"

authorized_users = set()

# -------------------------
# КНОПКИ
# -------------------------

keyboard = [
    ["Add User", "Remove User"],
    ["User List"]
]

markup = ReplyKeyboardMarkup(keyboard, resize_keyboard=True)


# -------------------------
# START
# -------------------------

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text("Введите код доступа:")


# -------------------------
# ОЧИСТКА ДИАЛОГА
# -------------------------

async def clear_chat(update, context):

    chat_id = update.effective_chat.id
    msg_id = update.message.message_id

    try:
        for i in range(1, 50):
            await context.bot.delete_message(chat_id, msg_id - i)
    except:
        pass


# -------------------------
# ОБРАБОТКА СООБЩЕНИЙ
# -------------------------

async def handle_message(update: Update, context: ContextTypes.DEFAULT_TYPE):

    user_id = update.message.from_user.id
    text = update.message.text

    # авторизация
    if user_id not in authorized_users:

        if text == PASSWORD:

            authorized_users.add(user_id)

            await update.message.delete()

            await clear_chat(update, context)

            await context.bot.send_message(
                chat_id=update.effective_chat.id,
                text="Панель управления",
                reply_markup=markup
            )
        else:
            await update.message.reply_text("Неверный пароль")

        return


    # -------------------------
    # КНОПКИ
    # -------------------------

    if text in ["Add User", "Remove User", "User List"]:
        await clear_chat(update, context)


    # -------------------------
    # ADD USER
    # -------------------------

    if text == "Add User":

        await update.message.reply_text(
            "Введите имя профиля:",
            reply_markup=markup
        )
        context.user_data["action"] = "add_user"

        return


    # -------------------------
    # REMOVE USER
    # -------------------------

    if text == "Remove User":

        result = subprocess.run(
            ["bash", "/root/xray-panel/list_users.sh"],
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

        formatted += "\nВведите номер профиля:"

        await update.message.reply_text(
            formatted,
            parse_mode="Markdown",
            reply_markup=markup
        )

        context.user_data["action"] = "remove_user"

        return


    # -------------------------
    # USER LIST
    # -------------------------

    if text == "User List":

        result = subprocess.run(
            ["bash", "/root/xray-panel/list_users.sh"],
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

        await update.message.reply_text(
            formatted,
            parse_mode="Markdown",
            reply_markup=markup
        )

        return


    # -------------------------
    # ВВОД ДАННЫХ
    # -------------------------

    action = context.user_data.get("action")

    if action == "add_user":

        username = text

        result = subprocess.run(
            ["bash", "/root/xray-panel/add_user.sh"],
            input=username,
            text=True,
            capture_output=True
        )
        output = result.stdout

        lines = output.splitlines()
        link = ""

        for line in lines:
            if line.startswith("vless://"):
                link = line

        await update.message.reply_text(
            f"{output.replace(link,'').strip()}\n\n`{link}`",
            parse_mode="Markdown",
            reply_markup=markup
        )

        context.user_data["action"] = None

        return


    if action == "remove_user":

        email = text

        result = subprocess.run(
            ["bash", "/root/xray-panel/del_user.sh"],
            input=email,
            text=True,
            capture_output=True
        )

        await update.message.reply_text(
            result.stdout,
            reply_markup=markup
        )
        context.user_data["action"] = None

        return


# -------------------------
# ЗАПУСК
# -------------------------

app = ApplicationBuilder().token(TOKEN).build()

app.add_handler(CommandHandler("start", start))
app.add_handler(MessageHandler(filters.TEXT, handle_message))

print("Bot started...")

app.run_polling()
