// Colour maths behind the bar icon's state colour.
//
// A plain JS file rather than functions inside SystemCheck.qml so the same code
// the widget runs can be exercised by node in tests/contrast.test.js. Nothing
// here touches QML, so it takes {r, g, b, a} objects, which is exactly the
// shape a QML `color` has when read from JavaScript.

// How far the icon must sit from the bar background, as a CIE76 distance in
// Lab. 30 is "clearly a different colour"; below it the two read as the same
// blob. Luminance contrast (WCAG) is the wrong measure here: the green glyph on
// the blue bar has a contrast ratio of only 1.19 yet is perfectly legible,
// because the hue carries it. A red glyph on a red bar has both a low ratio and
// a low distance, which is the case that actually needs fixing.
var MIN_DISTANCE = 30

// The most a state colour may be pushed lighter or darker, in HSV value steps.
var MAX_FACTOR = 5.8

function srgbToLinear(v) {
  return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4)
}

function toLab(c) {
  var r = srgbToLinear(c.r)
  var g = srgbToLinear(c.g)
  var b = srgbToLinear(c.b)
  // sRGB -> XYZ (D65)
  var x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
  var y = 0.2126 * r + 0.7152 * g + 0.0722 * b
  var z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
  function f(t) {
    return t > 0.008856 ? Math.pow(t, 1 / 3) : 7.787 * t + 16 / 116
  }
  var fx = f(x)
  var fy = f(y)
  var fz = f(z)
  return { L: 116 * fy - 16, a: 500 * (fx - fy), b: 200 * (fy - fz) }
}

// CIE76 colour difference. Good enough to answer "are these two the same
// colour to a person", and far cheaper than CIEDE2000.
function deltaE(one, other) {
  var p = toLab(one)
  var q = toLab(other)
  return Math.sqrt(
    Math.pow(p.L - q.L, 2) + Math.pow(p.a - q.a, 2) + Math.pow(p.b - q.b, 2)
  )
}

// WCAG contrast ratio, kept for the tests and for anyone reading the code who
// expects it; the guard itself uses deltaE.
function luminance(c) {
  return 0.2126 * srgbToLinear(c.r)
    + 0.7152 * srgbToLinear(c.g)
    + 0.0722 * srgbToLinear(c.b)
}

function contrastRatio(a, b) {
  var la = luminance(a)
  var lb = luminance(b)
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
}

function rgbToHsv(c) {
  var max = Math.max(c.r, c.g, c.b)
  var min = Math.min(c.r, c.g, c.b)
  var d = max - min
  var h = 0
  if (d !== 0) {
    if (max === c.r) h = ((c.g - c.b) / d) % 6
    else if (max === c.g) h = (c.b - c.r) / d + 2
    else h = (c.r - c.g) / d + 4
    h /= 6
    if (h < 0) h += 1
  }
  return { h: h, s: max === 0 ? 0 : d / max, v: max }
}

function hsvToRgb(h, s, v) {
  var i = Math.floor(h * 6)
  var f = h * 6 - i
  var p = v * (1 - s)
  var q = v * (1 - f * s)
  var t = v * (1 - (1 - f) * s)
  var r = 0
  var g = 0
  var b = 0
  switch (i % 6) {
    case 0: r = v; g = t; b = p; break
    case 1: r = q; g = v; b = p; break
    case 2: r = p; g = v; b = t; break
    case 3: r = p; g = q; b = v; break
    case 4: r = t; g = p; b = v; break
    default: r = v; g = p; b = q; break
  }
  return { r: r, g: g, b: b, a: 1 }
}

// Same semantics as Qt.lighter/Qt.darker: scale HSV value, keep hue and
// saturation, so the meaning of the colour survives the shift.
function lighter(c, factor) {
  var hsv = rgbToHsv(c)
  return hsvToRgb(hsv.h, hsv.s, Math.min(1, hsv.v * factor))
}

function darker(c, factor) {
  var hsv = rgbToHsv(c)
  return hsvToRgb(hsv.h, hsv.s, hsv.v / factor)
}

function toHex(c) {
  function channel(v) {
    var n = Math.round(Math.max(0, Math.min(1, v)) * 255)
    return (n < 16 ? "0" : "") + n.toString(16)
  }
  return "#" + channel(c.r) + channel(c.g) + channel(c.b)
}

// The colour to actually draw: the state colour untouched when it already
// separates from the bar, otherwise the smallest lightness shift that does.
// A transparent bar (a = 0) shows the wallpaper, so there is no backdrop to
// measure against and the colour is left alone.
function readableOn(stateColor, background) {
  if (!background || background.a === 0) return toHex(stateColor)
  if (deltaE(stateColor, background) >= MIN_DISTANCE) return toHex(stateColor)

  for (var step = 1; step <= 12; step++) {
    var factor = 1 + step * 0.4
    var light = lighter(stateColor, factor)
    if (deltaE(light, background) >= MIN_DISTANCE) return toHex(light)
    var dark = darker(stateColor, factor)
    if (deltaE(dark, background) >= MIN_DISTANCE) return toHex(dark)
  }

  // Mid-grey backdrops can defeat both directions; take whichever end is
  // furthest away rather than leaving the glyph invisible.
  var maxLight = lighter(stateColor, MAX_FACTOR)
  var maxDark = darker(stateColor, MAX_FACTOR)
  return deltaE(maxLight, background) >= deltaE(maxDark, background)
    ? toHex(maxLight)
    : toHex(maxDark)
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    MIN_DISTANCE: MIN_DISTANCE,
    srgbToLinear: srgbToLinear,
    toLab: toLab,
    deltaE: deltaE,
    luminance: luminance,
    contrastRatio: contrastRatio,
    rgbToHsv: rgbToHsv,
    hsvToRgb: hsvToRgb,
    lighter: lighter,
    darker: darker,
    toHex: toHex,
    readableOn: readableOn
  }
}
