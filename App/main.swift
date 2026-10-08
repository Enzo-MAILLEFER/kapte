// Kapte : fais une capture d'écran, la réponse s'affiche dans une bulle en bas à gauche.
// App de barre des menus (sans Dock), lancée au démarrage par le LaunchAgent com.kapte.
import AppKit

setvbuf(stdout, nil, _IOLBF, 0)  // logs écrits tout de suite dans ~/.kapte/kapte.log

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
