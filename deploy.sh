#!/bin/bash

# Arrête le script à la moindre erreur pour éviter un déploiement partiel.
set -e

# --- CONFIGURATION ---
# Modifiez ces variables pour qu'elles correspondent à votre environnement.

# 1. Configuration du projet Godot
# Assurez-vous que Godot est dans votre PATH système ou spécifiez le chemin complet.
# ex: GODOT_EXECUTABLE="/c/Program Files/Godot/Godot.exe"
GODOT_EXECUTABLE="/c/Program Files/Godot4/Godot_v4.6-stable_win64.exe"
# Le nom de votre preset d'exportation Web dans Godot.
EXPORT_PRESET_NAME="Web" 
# Le dossier où le build sera généré. On le place HORS du projet (../) 
# car Godot n'aime pas exporter à l'intérieur du dossier du projet.
BUILD_DIR="../Builds/Build_Web"

# 2. Configuration Itch.io (Butler)
# Le chemin vers là où vous avez extrait butler.exe (format Git Bash)
BUTLER_EXECUTABLE="/c/butler/butler.exe" 
ITCH_USER="trankil"
ITCH_GAME="folklore-on-tap"

EXPORT_PRESET_WIN="Windows Desktop"
BUILD_DIR_WIN="../Builds/Windows"

EXPORT_PRESET_ANDROID="Android"
BUILD_DIR_ANDROID="../Builds/Android"

# 3. Configuration du serveur distant (VPS)
SSH_USER="root"
SSH_HOST="51.91.103.104"
# Le dossier sur le VPS où les fichiers du jeu doivent être téléversés.
REMOTE_WEB_ROOT="/root/server/site" 
# Le dossier sur le VPS qui contient votre fichier docker-compose.yml.
REMOTE_DOCKER_DIR="/root/server"

# --- SCRIPT DE DÉPLOIEMENT ---
# Ne modifiez rien en dessous de cette ligne.

echo "🚀 Lancement du déploiement..."

# 1. Exporter et déployer pour le Web (VPS)
echo "📦 Exportation du projet pour le Web..."
# On s'assure que le dossier de build est propre.
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
# Lancement de l'export en ligne de commande.
"$GODOT_EXECUTABLE" --headless --export-release "$EXPORT_PRESET_NAME" "$BUILD_DIR/index.html"
echo "✅ Exportation terminée."

# 2. Téléverser les fichiers sur le VPS avec scp (car rsync n'est pas par défaut sous Windows)
echo "⏫ Téléversement des fichiers sur le VPS..."
# On s'assure que le dossier distant existe et on le vide (équivalent du --delete)
ssh "$SSH_USER@$SSH_HOST" "mkdir -p $REMOTE_WEB_ROOT && rm -rf $REMOTE_WEB_ROOT/*"
# On copie tous les nouveaux fichiers du build vers le serveur
scp -r "$BUILD_DIR"/* "$SSH_USER@$SSH_HOST:$REMOTE_WEB_ROOT/"
echo "✅ Téléversement terminé."

# 3. Redémarrer les services Docker sur le VPS
echo "🐳 Redémarrage des services Docker..."
ssh "$SSH_USER@$SSH_HOST" "cd $REMOTE_DOCKER_DIR && docker-compose down && docker-compose up -d"
echo "✅ Services redémarrés."

# 4. Exporter et déployer pour Itch.io (Windows & Android)
echo "📦 Exportation du projet pour Windows..."
rm -rf "$BUILD_DIR_WIN"
mkdir -p "$BUILD_DIR_WIN"
"$GODOT_EXECUTABLE" --headless --export-release "$EXPORT_PRESET_WIN" "$BUILD_DIR_WIN/FolkloreOnTap.exe"

echo "📦 Exportation du projet pour Android..."
rm -rf "$BUILD_DIR_ANDROID"
mkdir -p "$BUILD_DIR_ANDROID"
# Utilisation de --export-debug pour contourner l'absence de Keystore de Release
"$GODOT_EXECUTABLE" --headless --export-debug "$EXPORT_PRESET_ANDROID" "$BUILD_DIR_ANDROID/FolkloreOnTap.apk"

echo "🚀 Envoi vers itch.io avec Butler..."
"$BUTLER_EXECUTABLE" push "$BUILD_DIR_WIN" "$ITCH_USER/$ITCH_GAME:windows"
"$BUTLER_EXECUTABLE" push "$BUILD_DIR_ANDROID" "$ITCH_USER/$ITCH_GAME:android"
echo "✅ Envoi Itch.io terminé."

echo "🎉 Déploiement terminé ! Le projet est en ligne."
