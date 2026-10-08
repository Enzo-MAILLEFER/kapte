// Bulle de la v1 (JavaScript). Gardée seulement pour la migration v1 → v2 (voir kapte.py).
// Usage : osascript -l JavaScript overlay.js "texte" [secondes]
ObjC.import('Cocoa');

function run(argv) {
  var text = argv[0] || '';
  var seconds = parseFloat(argv[1] || '12');
  // Mode chargement : petits points animés au lieu d'un message
  var loading = text === '--loading';
  var frames = ['•  ', '•• ', '•••'];
  if (loading) text = frames[2];

  $.NSApplication.sharedApplication;
  $.NSApp.setActivationPolicy($.NSApplicationActivationPolicyAccessory);

  var screen = $.NSScreen.mainScreen.visibleFrame;
  var maxW = 280, margin = 12, padX = 10, padY = 7;

  // Texte (créé d'abord pour mesurer sa taille)
  var label = $.NSTextField.alloc.initWithFrame($.NSMakeRect(0, 0, maxW, 1000));
  label.setEditable(false);
  label.setSelectable(false);
  label.setBezeled(false);
  label.setDrawsBackground(false);
  label.setTextColor($.NSColor.colorWithCalibratedWhiteAlpha(1, 0.9));
  label.setFont($.NSFont.systemFontOfSize(12));
  label.setStringValue($(text));
  label.cell.setWraps(true);
  label.cell.setLineBreakMode($.NSLineBreakByWordWrapping);

  // La bulle prend juste la taille du texte
  var size = label.cell.cellSizeForBounds($.NSMakeRect(0, 0, maxW, 1000));
  var tw = Math.ceil(size.width), th = Math.ceil(size.height);
  var w = tw + 2 * padX, h = th + 2 * padY;
  var x = screen.origin.x + margin;
  var y = screen.origin.y + margin;
  label.setFrame($.NSMakeRect(padX, padY, tw, th));

  var win = $.NSWindow.alloc.initWithContentRectStyleMaskBackingDefer(
    $.NSMakeRect(x, y, w, h),
    $.NSWindowStyleMaskBorderless,
    $.NSBackingStoreBuffered,
    false
  );
  win.setLevel($.NSStatusWindowLevel);
  win.setOpaque(false);
  win.setHasShadow(false);
  win.setIgnoresMouseEvents(true);  // les clics passent à travers
  win.setBackgroundColor($.NSColor.clearColor);
  win.setCollectionBehavior(
    $.NSWindowCollectionBehaviorCanJoinAllSpaces |
    $.NSWindowCollectionBehaviorFullScreenAuxiliary
  );

  // Fond arrondi (NSBox + NSColor : passer un CGColor via le pont JXA
  // fait planter osascript sur Apple Silicon, EXC_ARM_PAC_FAIL)
  var content = $.NSBox.alloc.initWithFrame($.NSMakeRect(0, 0, w, h));
  content.setBoxType($.NSBoxCustom);
  content.setBorderWidth(0);
  content.setCornerRadius(8);
  content.setFillColor($.NSColor.colorWithCalibratedWhiteAlpha(0.12, 0.7));
  content.setContentViewMargins($.NSMakeSize(0, 0));
  win.setContentView(content);
  content.contentView.addSubview(label);

  win.orderFrontRegardless;

  // Garde la fenêtre affichée pendant N secondes
  if (loading) {
    for (var i = 0; i < seconds / 0.35; i++) {
      label.setStringValue($(frames[i % 3]));
      $.NSRunLoop.currentRunLoop.runUntilDate(
        $.NSDate.dateWithTimeIntervalSinceNow(0.35)
      );
    }
  } else {
    $.NSRunLoop.currentRunLoop.runUntilDate(
      $.NSDate.dateWithTimeIntervalSinceNow(seconds)
    );
  }
  win.close;
  return '';
}
