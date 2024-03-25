
import matplotlib.pyplot as plt
import matplotlib.animation as animation
import numpy as np
import matplotlib;
matplotlib.use("TkAgg")
import time
import serial
import  pyttsx3
import pygame
import tkinter as tk
from tkinter import simpledialog
from tkinter import messagebox
from tkinter import ttk
import secrets
import string
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
import sys

def displace_message(message):

    root = tk.Tk()
    root.withdraw()

    messagebox.showinfo("Important notice", message)

    root.destroy()

def get_user_input(prompt):
    root = tk.Tk()
    root.withdraw()

    user_input = simpledialog.askstring("Input", prompt)

    return user_input

def generate_random_number_password(length=6):
    # Use only digits for the password
    digits = string.digits
    password = ''.join(secrets.choice(digits) for i in range(length))
    return password

def send_email(subject, message, to_email):
    from_email = "jeffrey.he0418@gmail.com"
    password = "jkvksukxtbeboddi"

    # Create the email message
    msg = MIMEMultipart()
    msg['From'] = from_email
    msg['To'] = to_email
    msg['Subject'] = subject
    body = MIMEText(message, 'plain')
    msg.attach(body)

    # Send the email
    with smtplib.SMTP('smtp.gmail.com', 587) as server:
        server.starttls()
        server.login(from_email, password)
        text = msg.as_string()
        server.sendmail(from_email, to_email, text)

def speak(text):
    engine = pyttsx3.init()  # Initialize the converter
    engine.setProperty('rate', 100)  # Speed percent (can go over 100)
    engine.setProperty('volume', 1)  # Volume 0-1

    engine.say(text)  # Add the text to the speech queue
    engine.runAndWait()

def play_music_for_duration(file_path, duration):
    pygame.mixer.init()  # Initialize the mixer module
    pygame.mixer.music.load(file_path)  # Load the music file
    pygame.mixer.music.play()  # Start playing the music

    time.sleep(duration)  # Wait for the duration (in seconds) you want the music to play
    pygame.mixer.music.stop()  # Stop the music after the duration has passed

def submit_and_quit():
    global speed_1_int, volume_1_int, repeat_1_int
    # Retrieve the inputs from the entry widgets
    speed_1 = speed.get()
    volume_1 = volume.get()
    repeat_1 = repeat.get()

    repeat_1_int = int(repeat_1.strip())
    volume_1_int = int(volume_1.strip())
    speed_1_int = int(repeat_1.strip())

    # Print the inputs for demonstration purposes
    print(f"Speed: {speed_1}, Volume: {volume_1}, Repeat: {repeat_1}")

    root.quit()
    root.destroy()

repeat_1_int =0
volume_1_int = 0
speed_1_int = 0



password = generate_random_number_password()

#get email
ask_email = "Please Enter The Email Where You Want To Get Your Password:"
email = get_user_input(ask_email)

#end email
send_email("Oven Controller Password", f"Your password is: {password}", email)

#check email
password_chance = 3
while password_chance >0:
    get_password = f"please enter the password sent to your email:\nyou have {password_chance} chances."
    email_password = get_user_input(get_password)
    if email_password == password:
        displace_message("password correct :)")
        break
    else:
        displace_message("password wrong :(")
        password_chance = password_chance - 1

if password_chance == 0:
    displace_message("all attempt used, please restart the program")
    sys.exit()

# Set up the serial port connection
ser = serial.Serial(
    port='COM6',  # Change to your port
    baudrate=115200,
    parity=serial.PARITY_NONE,
    stopbits=serial.STOPBITS_TWO,
    bytesize=serial.EIGHTBITS
)

# Initialize lists to store time and formatted_number values
time_data = []
formatted_numbers = []

fig, ax = plt.subplots()
line, = ax.plot([], [], 'r-', label='Temperature (°C)')
ax.set_xlabel('Time (ms)')
ax.set_ylabel('Temp')
ax.set_title('Temp')
ax.legend()
ax.grid(True)

a = 0
b = 0
c = 0
d = 0
e = 0
f = 0
g = 0
def init():
    ax.set_xlim(0, 2000)  # Initial x-axis limit
    ax.set_ylim(0, 300)  # Initial y-axis limit
    return line,

def update(frame, formatted_number=None):
    global a, b, c, d, e, temp_counter, f, g

    if ser.in_waiting:
        strin = ser.readline()
        decoded_strin = strin.decode('utf-8').strip()

        def draw_vertical_line():
            ax.axvline(x=frame, color='r', linestyle='--')

        try:
            if len(decoded_strin) == 4:
                formatted_str = decoded_strin[:2] + '.' + decoded_strin[2:]
                formatted_number = float(formatted_str)*100
                if formatted_number > 50 and a < 2:
                    speak("stage one: ramp to soak")
                    a += 1
                    draw_vertical_line()

                if formatted_number > 150 and b < 2:
                    speak("stage two: soaking")
                    b += 1
                    draw_vertical_line()

                if formatted_number > 165 and c < 2:
                    speak("stage three: ramp to peak")
                    c += 1
                    draw_vertical_line()

                if formatted_number > 220 and d < 2:
                    speak("stage four: reflow")
                    d += 1
                    temp_counter = 1
                    draw_vertical_line()
                    ax.axhline(y=240, color='r', linestyle='--')

                if formatted_number > 240:
                    speak("temperature too high")
                    displace_message("temperature too high, please terminate program")

                if formatted_number < 215 and d==2 and f < 2:
                    speak("cooling ")
                    f+=1

                if formatted_number < 40 and d==2 and g < 2:
                    speak("process is complete")
                    music_file = "C:/291/project1/祖海-好运来.ogg"
                    play_music_for_duration(music_file, 20)


                # Update the data lists
                time_data.append(frame)
                formatted_numbers.append(formatted_number)

                # Update plot data
                line.set_data(time_data, formatted_numbers)

                ax.set_title(f'Current:{formatted_number:.2f}°C  Max:{max(formatted_numbers)}°C  Min:{min(formatted_numbers)}°C')
                # Adjust limits
                if frame >= ax.get_xlim()[1]:
                    ax.set_xlim(0, ax.get_xlim()[1] + 10)  # Keep x-axis minimum fixed at 0

                if formatted_number >= ax.get_ylim()[1] or formatted_number <= ax.get_ylim()[0]:
                    ax.set_ylim(min(formatted_numbers) - 10, max(formatted_numbers) + 10)

        except ValueError as e:
            print(f"Error processing input {decoded_strin}: {e}")

    return line,



ani = animation.FuncAnimation(fig, update, init_func=init, frames=np.arange(1, 2000), blit=False, interval=200)

plt.show()