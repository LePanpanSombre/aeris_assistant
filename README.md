# Aeris Assistant Vocal Offline (FR + Bluetooth)

**Aeris** est un assistant vocal 100% offline pour Raspberry Pi 5, avec :  
- Reconnaissance vocale française (**Whisper.cpp**)  
- LLM local (**GPT4All**)  
- Synthèse vocale féminine française (**Coqui TTS**)  
- Gestion du Bluetooth pour les enceintes  
- Hotword : "Aeris"

---

## Installation

1. Cloner le projet :
```bash
git clone https://github.com/<ton-compte>/aeris_assistant.git
cd aeris_assistant

chmod +x install.sh
./install.sh


systemctl status aeris
