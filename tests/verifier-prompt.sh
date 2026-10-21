#!/bin/bash
# Vérifie le prompt de Kapte sur les captures de tests/captures/ (une requête Gemini par capture).
# À lancer après chaque modification du prompt : ./tests/verifier-prompt.sh
# Une seule capture (ou quelques-unes) : ./tests/verifier-prompt.sh pluriel lettre
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p build
swiftc -O -swift-version 5 -o build/verifier-prompt tests/main.swift App/Gemini.swift App/Config.swift
build/verifier-prompt tests "$@"
