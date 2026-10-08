// Icône Kapte dans la barre des menus : activer / mettre en pause / mettre à jour.
// Usage : osascript -l JavaScript menubar.js  (lancé par le LaunchAgent com.kapte.menubar)
// La pause = présence du fichier ~/.kapte/paused, lu par kapte.py.
ObjC.import('Cocoa');

var DIR = $.NSHomeDirectory().js + '/.kapte';
var FLAG = DIR + '/paused';
var VERSION_URL = 'https://raw.githubusercontent.com/Enzo-MAILLEFER/kapte/main/VERSION';
var CHECK_EVERY = 6 * 3600;  // secondes entre deux vérifications automatiques

var fm = $.NSFileManager.defaultManager;
var app = Application.currentApplication();
app.includeStandardAdditions = true;

var item, statusLine, toggleItem, updateItem, handler, timer;
var remoteVersion = null;

function sh(s) {
  return "'" + String(s).replace(/'/g, "'\\''") + "'";
}

function readFile(path) {
  var s = $.NSString.stringWithContentsOfFileEncodingError($(path), $.NSUTF8StringEncoding, null);
  return s.isNil() ? '' : s.js.trim();
}

function localVersion() {
  return readFile(DIR + '/VERSION') || '0';
}

// "1.10.0" > "1.9.2"
function isNewer(a, b) {
  var x = a.split('.'), y = b.split('.');
  for (var i = 0; i < Math.max(x.length, y.length); i++) {
    var d = (parseInt(x[i], 10) || 0) - (parseInt(y[i], 10) || 0);
    if (d) return d > 0;
  }
  return false;
}

function bubble(text, seconds) {
  app.doShellScript('osascript -l JavaScript ' + sh(DIR + '/overlay.js') + ' ' + sh(text) + ' ' +
    (seconds || 6) + ' >/dev/null 2>&1 &');
}

function isPaused() {
  return fm.fileExistsAtPath($(FLAG));
}

function setPaused(paused) {
  if (paused) {
    fm.createFileAtPathContentsAttributes($(FLAG), $.NSData.data, $());
  } else {
    fm.removeItemAtPathError($(FLAG), $());
  }
}

function refresh() {
  var paused = isPaused();
  var img = $.NSImage.imageWithSystemSymbolNameAccessibilityDescription(
    paused ? 'eye.slash' : 'eye', $('Kapte')
  );
  img.setTemplate(true);
  item.button.setImage(img);
  item.button.setAlphaValue(paused ? 0.5 : 1);
  statusLine.setTitle($((paused ? 'Kapte : en pause' : 'Kapte : activé') + '  ·  v' + localVersion()));
  toggleItem.setTitle($(paused ? 'Activer' : 'Mettre en pause'));
  updateItem.setTitle($(remoteVersion ? 'Mettre à jour vers v' + remoteVersion + '…'
                                      : 'Rechercher les mises à jour'));
}

// Renvoie la version en ligne si elle est plus récente, sinon null.
// Lève une erreur si GitHub est injoignable.
function fetchNewerVersion() {
  var remote = app.doShellScript('curl -fsSL --max-time 8 ' + sh(VERSION_URL)).trim();
  if (!/^\d+(\.\d+)*$/.test(remote)) throw new Error('version invalide');
  return isNewer(remote, localVersion()) ? remote : null;
}

function startUpdate() {
  // Lancé dans une session séparée : update.sh redémarre cette icône à la fin,
  // il ne doit pas être tué avec elle.
  app.doShellScript("/usr/bin/python3 -c 'import subprocess, sys; " +
    "subprocess.Popen([\"/bin/bash\", sys.argv[1]], start_new_session=True, " +
    "stdout=open(sys.argv[2], \"a\"), stderr=subprocess.STDOUT)' " +
    sh(DIR + '/update.sh') + ' ' + sh(DIR + '/update.log'));
  bubble('Mise à jour de Kapte…', 30);
}

function askUpdate(version) {
  $.NSApp.activateIgnoringOtherApps(true);
  var alert = $.NSAlert.alloc.init;
  alert.setMessageText($('Kapte v' + version + ' est disponible'));
  alert.setInformativeText($('Tu as la v' + localVersion() +
    '. La mise à jour prend quelques secondes, tes réglages sont conservés.'));
  alert.addButtonWithTitle($('Mettre à jour'));
  alert.addButtonWithTitle($('Plus tard'));
  if (alert.runModal == $.NSAlertFirstButtonReturn) startUpdate();
}

ObjC.registerSubclass({
  name: 'KapteMenuHandler',
  methods: {
    'toggle:': {
      types: ['void', ['id']],
      implementation: function (sender) {
        setPaused(!isPaused());
        refresh();
      }
    },
    'update:': {
      types: ['void', ['id']],
      implementation: function (sender) {
        try {
          remoteVersion = fetchNewerVersion();
        } catch (e) {
          bubble('Impossible de vérifier les mises à jour (connexion ?)', 6);
          return;
        }
        refresh();
        if (remoteVersion) askUpdate(remoteVersion);
        else bubble('Kapte est à jour (v' + localVersion() + ')', 4);
      }
    },
    'autoCheck:': {
      types: ['void', ['id']],
      implementation: function (sender) {
        try {
          remoteVersion = fetchNewerVersion();
        } catch (e) {
          return;  // hors ligne : on réessaiera plus tard
        }
        refresh();
        // Prévient une seule fois par nouvelle version
        if (remoteVersion && readFile(DIR + '/notified_version') !== remoteVersion) {
          $(remoteVersion).writeToFileAtomicallyEncodingError(
            $(DIR + '/notified_version'), true, $.NSUTF8StringEncoding, null);
          bubble('Nouvelle version de Kapte (v' + remoteVersion + ') : icône 👁 → Mettre à jour', 10);
        }
      }
    },
    'quit:': {
      types: ['void', ['id']],
      implementation: function (sender) {
        // Sans icône on ne verrait plus l'état : quitter = mettre en pause.
        // L'icône revient à la prochaine ouverture de session.
        setPaused(true);
        $.NSApp.terminate(null);
      }
    }
  }
});

function menuItem(title, action) {
  var mi = $.NSMenuItem.alloc.initWithTitleActionKeyEquivalent($(title), action, $(''));
  if (action) mi.setTarget(handler);
  else mi.setEnabled(false);
  return mi;
}

function run() {
  $.NSApplication.sharedApplication;
  $.NSApp.setActivationPolicy($.NSApplicationActivationPolicyAccessory);

  handler = $.KapteMenuHandler.alloc.init;
  item = $.NSStatusBar.systemStatusBar.statusItemWithLength($.NSVariableStatusItemLength);

  var menu = $.NSMenu.alloc.init;
  menu.setAutoenablesItems(false);
  menu.addItem(statusLine = menuItem('', null));
  menu.addItem(toggleItem = menuItem('', 'toggle:'));
  menu.addItem($.NSMenuItem.separatorItem);
  menu.addItem(updateItem = menuItem('', 'update:'));
  menu.addItem($.NSMenuItem.separatorItem);
  menu.addItem(menuItem('Quitter (met en pause)', 'quit:'));

  item.setMenu(menu);
  refresh();

  // Vérification automatique : peu après le démarrage, puis toutes les 6 h
  $.NSTimer.scheduledTimerWithTimeIntervalTargetSelectorUserInfoRepeats(
    10, handler, 'autoCheck:', null, false);
  timer = $.NSTimer.scheduledTimerWithTimeIntervalTargetSelectorUserInfoRepeats(
    CHECK_EVERY, handler, 'autoCheck:', null, true);

  $.NSApp.run;
}
