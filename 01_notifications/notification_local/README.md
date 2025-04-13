# 📱 Flutter Notifications Locales
Une application Flutter simple permettant d'afficher des notifications locales sur Android et iOS, avec la possibilité de naviguer vers un autre écran à partir d'une notification.

## 🚀 Fonctionnalités
- Affichage de notifications avec ou sans titre/contenu.
- Notifications silencieuses (avec ou sans son).
- Navigation automatique vers un écran dédié lorsque l'utilisateur clique sur une notification.
- Gestion de l'état de lancement de l'application depuis une notification.
- Suppression de toutes les notifications existantes.

---

## 📦 Dépendances principales

- [`flutter_local_notifications`](https://pub.dev/packages/flutter_local_notifications)

---

## 🛠️ Installation
1. Clone ce repo :
   ```bash
   git clone https://github.com/brahamax1209/flutter_notifications_demo.git
   cd flutter_notifications_demo
Installe les dépendances :
flutter pub get
Exécute le projet :
flutter run

📸 Aperçu de l'interface
L'application principale affiche plusieurs boutons :
Afficher une notification
Afficher une notification sans titre/contenu
Notification silencieuse
Annuler toutes les notifications
Lorsqu'on clique sur une notification, l'app affiche un deuxième écran (SecondPage) avec les détails du payload.

🔔 Notifications - Comportement
Chaque notification envoyée contient un payload (ici : "Article12345").
Si l'utilisateur clique sur une notification pendant que l'app est fermée, elle s'ouvre automatiquement sur l'écran SecondPage avec ce payload.
Si l'app est ouverte, elle navigue aussi automatiquement vers SecondPage.

⚙️ iOS - Configuration supplémentaire
Pour faire fonctionner les notifications sur iOS :
Ouvre le fichier ios/Runner/Info.plist.
Ajoute les permissions :
<key>UIBackgroundModes</key>
<array>
<string>remote-notification</string>
</array>
<key>NSAppTransportSecurity</key>
<dict>
<key>NSAllowsArbitraryLoads</key>
<true/>
</dict>
<key>NSUserNotificationAlertStyle</key>
<string>alert</string>

Active les notifications dans Xcode :
Cible ➜ Signing & Capabilities ➜ + Capability ➜ Push Notifications

📌 À savoir
Le payload est une chaîne de caractères envoyée avec la notification, utile pour transférer des données (ex: ID d'article, type d'action).
Ce projet utilise un StreamController pour gérer les clics de notification de manière réactive.
La classe PaddedElevatedButton simplifie la création de boutons avec un padding vertical.

📁 Structure
lib/
├── main.dart            # Entrée principale de l'application
├── widgets/
│   └── padded_button.dart (optionnel)

🧪 Tester
Teste l'affichage de différentes notifications.
Clique sur une notification avec l'app fermée pour tester la navigation automatique.
Teste la suppression de toutes les notifications.

💡 Auteur
Développé par [Braham MOUSSOUNI]
📧 Contact : [brahammoussouni@icloud.com.com]
