#!/bin/bash
set -e

echo "🚀 Installation de l'assistant vocal Aeris (FR + Bluetooth + voix féminine)..."

# === 1. Préparation du système ===
sudo apt update && sudo apt upgrade -y
sudo apt install git build-essential cmake ffmpeg libatlas-base-dev portaudio19-dev python3-dev python3-venv wget unzip pulseaudio pulseaudio-module-bluetooth bluez blueman -y

# === 2. Création du dossier & environnement virtuel ===
cd ~
mkdir -p aeris_assistant && cd aeris_assistant
python3 -m venv venv
source venv/bin/activate

# === 3. Dépendances Python ===
pip install --upgrade pip
pip install gpt4all TTS pyaudio pvporcupine sounddevice numpy soundfile

# === 4. Whisper.cpp ===
if [ ! -d "whisper.cpp" ]; then
  git clone https://github.com/ggerganov/whisper.cpp
fi
cd whisper.cpp && make -j$(nproc)
mkdir -p models
if [ ! -f "models/ggml-tiny.bin" ]; then
  wget https://huggingface.co/ggerganov/whisper.cpp/resolve/main/models/ggml-tiny.bin -P models/
fi
cd ..

# === 5. GPT4All (modèle multilingue compatible FR) ===
if [ ! -f "ggml-model.bin" ]; then
  wget https://gpt4all.io/models/ggml-gpt4all-j-v1.3-groovy.bin -O ggml-model.bin
fi

# === 6. Script principal Aeris ===
cat > aeris.py << 'EOF'
import subprocess
import sounddevice as sd
import numpy as np
import pvporcupine
import struct
from gpt4all import GPT4All
from TTS.api import TTS
import soundfile as sf
import os

# === Initialisation ===
print("🚀 Initialisation de l'assistant Aeris en français...")
model = GPT4All("ggml-model.bin")
tts = TTS(model_name="tts_models/fr/css10/vits")  # voix féminine FR

porcupine = pvporcupine.create(keywords=["aeris"])  # hotword = "aeris"
samplerate = 16000
duration = 5  # secondes d'enregistrement

# périphérique audio par défaut
default_sink = "alsa_output"
current_sink = default_sink

def record_audio(filename, duration=duration):
    print("🎙️ Enregistrement…")
    recording = sd.rec(int(duration * samplerate), samplerate=samplerate, channels=1, dtype='float32')
    sd.wait()
    np.save(filename, recording)
    print("✅ Enregistrement terminé.")

def stt(filename):
    data = np.load(filename)
    sf.write("temp.wav", data, samplerate)
    result = subprocess.run(
        ["./whisper.cpp/main", "-m", "whisper.cpp/models/ggml-tiny.bin", "-l", "fr", "-f", "temp.wav"],
        capture_output=True, text=True
    )
    lines = result.stdout.splitlines()
    transcription = lines[-1] if lines else ""
    return transcription

def speak(text):
    global current_sink
    print(f"🔊 Aeris répond : {text}")
    tts.tts_to_file(text=text, file_path="response.wav")
    if current_sink == default_sink:
        subprocess.run(["aplay", "response.wav"])
    else:
        subprocess.run(["paplay", "--device", current_sink, "response.wav"])

def listen_hotword():
    with sd.InputStream(samplerate=samplerate, channels=1, dtype='int16') as stream:
        print("👂 En attente du hotword 'Aeris'…")
        while True:
            pcm = stream.read(512)[0]
            pcm = struct.unpack_from("h" * 512, pcm)
            keyword_index = porcupine.process(pcm)
            if keyword_index >= 0:
                print("🔔 Hotword détecté !")
                return

def set_bluetooth_sink():
    global current_sink
    sinks = subprocess.check_output(["pactl", "list", "short", "sinks"]).decode()
    for line in sinks.splitlines():
        if "bluez_sink" in line:
            current_sink = line.split()[1]
            subprocess.run(["pactl", "set-default-sink", current_sink])
            speak("Je suis maintenant connectée à ton enceinte Bluetooth.")
            return
    speak("Je n'ai trouvé aucune enceinte Bluetooth connectée.")

def reset_to_speakers():
    global current_sink
    current_sink = default_sink
    subprocess.run(["pactl", "set-default-sink", current_sink])
    speak("Je repasse sur les haut-parleurs du Raspberry Pi.")

def check_output_device():
    global current_sink
    if "bluez_sink" in current_sink:
        speak("La sortie audio actuelle est une enceinte Bluetooth.")
    else:
        speak("La sortie audio actuelle est les haut-parleurs du Raspberry Pi.")

def main():
    print("🤖 Aeris est prête à vous écouter.")
    while True:
        listen_hotword()
        record_audio("input.npy", duration=5)
        query = stt("input.npy")
        print("🗨️ Vous :", query)

        if query.strip() == "":
            continue

        # Commandes vocales spéciales
        if "bluetooth" in query.lower():
            set_bluetooth_sink()
            continue
        if "haut-parleur" in query.lower():
            reset_to_speakers()
            continue
        if "sortie" in query.lower():
            check_output_device()
            continue
        if query.lower() in ["quit", "exit", "stop", "au revoir"]:
            speak("Au revoir, à bientôt !")
            break

        # Réponse IA (toujours en français)
        response = model.generate("Réponds uniquement en français : " + query, max_tokens=200)
        speak(response)

if __name__ == "__main__":
    main()
EOF

# === 7. Script de lancement ===
cat > run.sh << 'EOF'
#!/bin/bash
cd ~/aeris_assistant
source venv/bin/activate
python aeris.py
EOF
chmod +x run.sh

echo "✅ Installation terminée !"
echo "👉 Lance ton assistant Aeris avec : ./run.sh"
echo "ℹ️ Pense à coupler ton enceinte Bluetooth avec 'bluetoothctl' ou Blueman avant usage."
