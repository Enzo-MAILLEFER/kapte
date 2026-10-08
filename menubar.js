// Icône Kapte dans la barre des menus : activer / mettre en pause.
// Usage : osascript -l JavaScript menubar.js  (lancé par le LaunchAgent com.kapte.menubar)
// La pause = présence du fichier ~/.kapte/paused, lu par kapte.py.
ObjC.import('Cocoa');

var FLAG = $.NSHomeDirectory().js + '/.kapte/paused';
var fm = $.NSFileManager.defaultManager;
var item, statusLine, toggleItem, handler;

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
  statusLine.setTitle($(paused ? 'Kapte : en pause' : 'Kapte : activé'));
  toggleItem.setTitle($(paused ? 'Activer' : 'Mettre en pause'));
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

function run() {
  $.NSApplication.sharedApplication;
  $.NSApp.setActivationPolicy($.NSApplicationActivationPolicyAccessory);

  handler = $.KapteMenuHandler.alloc.init;
  item = $.NSStatusBar.systemStatusBar.statusItemWithLength($.NSVariableStatusItemLength);

  var menu = $.NSMenu.alloc.init;
  menu.setAutoenablesItems(false);

  statusLine = $.NSMenuItem.alloc.initWithTitleActionKeyEquivalent($(''), null, $(''));
  statusLine.setEnabled(false);
  menu.addItem(statusLine);

  toggleItem = $.NSMenuItem.alloc.initWithTitleActionKeyEquivalent($(''), 'toggle:', $(''));
  toggleItem.setTarget(handler);
  menu.addItem(toggleItem);

  menu.addItem($.NSMenuItem.separatorItem);

  var quitItem = $.NSMenuItem.alloc.initWithTitleActionKeyEquivalent(
    $('Quitter (met en pause)'), 'quit:', $('')
  );
  quitItem.setTarget(handler);
  menu.addItem(quitItem);

  item.setMenu(menu);
  refresh();
  $.NSApp.run;
}
