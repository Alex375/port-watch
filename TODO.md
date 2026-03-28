# PortWatch — Avancement

## Etapes

- [x] **1. Projet Xcode** — structure, Info.plist, LSUIElement, scheme qui build et run
- [x] **2. Menubar de base** — icône dans la barre, menu déroulant vide, "Quitter"
- [x] **3. Scan des ports** — libproc, lister les ports TCP ouverts avec PID/process
- [x] **4. Détection de projet** — Docker, fichiers marqueurs, ports connus (Docker: à tester)
- [x] **5. Affichage groupé** — grouper par projet dans le menu
- [x] **6. Kill de processus** — séquence SIGTERM/SIGKILL avec vérification + ouvrir dans navigateur
- [x] **7. Zombies + CPU/RAM** — détection et indicateurs visuels
- [x] **8. Notifications** — optionnelles, UNUserNotificationCenter
  - [x] Notification quand un nouveau port est détecté
  - [x] Notification spéciale quand un processus s'ouvre sur un port déjà occupé (conflit de port)
- [x] **9. Réglages + désinstallation** — seuils configurables, uninstall propre
  - [x] Mots-clés de reconnaissance Front/Back/DB/Cache configurables dans les réglages

## Plus tard
- [ ] **Auto-update** — script shell qui check GitHub Releases et remplace le .app automatiquement
