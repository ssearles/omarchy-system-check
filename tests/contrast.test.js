// Tests for lib/contrast.js - the colour maths behind the bar icon.
//
// Run directly:   node tests/contrast.test.js
// The shell suite also runs this file when node is available.
//
// The point of these tests is the failure the eye catches but a screenshot
// review misses: a state colour that matches the bar background. Every case
// below is one a theme can actually produce.

const C = require("../lib/contrast.js")

let pass = 0
let fail = 0
const failures = []

function ok(name) {
  pass++
  console.log("  ok   " + name)
}

function no(name, detail) {
  fail++
  failures.push(name)
  console.log("  FAIL " + name + (detail ? "\n       " + detail : ""))
}

function check(name, condition, detail) {
  if (condition) ok(name)
  else no(name, detail)
}

function hex(value) {
  const s = String(value).replace("#", "")
  return {
    r: parseInt(s.slice(0, 2), 16) / 255,
    g: parseInt(s.slice(2, 4), 16) / 255,
    b: parseInt(s.slice(4, 6), 16) / 255,
    a: 1
  }
}

const STATES = { red: "#e05252", amber: "#e5c07b", green: "#8ec07c" }

// ---------------------------------------------------------------------------
console.log("live bar (Lupine blue, #56ADD7)")
const blue = hex("#56ADD7")
for (const [name, value] of Object.entries(STATES)) {
  const out = C.readableOn(hex(value), blue)
  check(name + " on the live bar is untouched", out === value, "got " + out)
}

// ---------------------------------------------------------------------------
console.log("\ncollision: the bar background is the state colour itself")
for (const [name, value] of Object.entries(STATES)) {
  const bg = hex(value)
  const out = C.readableOn(hex(value), bg)
  check(name + " on " + name + " is shifted", out !== value, "unchanged")
  check(
    name + " on " + name + " clears the floor",
    C.deltaE(hex(out), bg) >= C.MIN_DISTANCE,
    "dE " + C.deltaE(hex(out), bg).toFixed(1) + " (" + out + ")"
  )
  // The hue is the meaning, so it has to survive the lightness shift.
  const before = C.rgbToHsv(hex(value)).h
  const after = C.rgbToHsv(hex(out)).h
  const hueShift = Math.min(Math.abs(before - after), 1 - Math.abs(before - after))
  check(name + " keeps its hue", hueShift < 0.01, "hue moved " + (hueShift * 360).toFixed(1) + " deg")
}

// ---------------------------------------------------------------------------
console.log("\nother bar backgrounds are left alone")
const others = {
  "near black": "#101315",
  "near white": "#f8f9f9",
  "mid grey": "#808080",
  "dark grey": "#333333",
  "lupine accent": "#3264eb",
  "lupine magenta": "#c900c4",
  "lupine blue-yellow": "#026fde",
  "lupine purple-green": "#4a2fd0",
  "orange": "#e07b39",
  "teal": "#2f8f8f"
}
for (const [bgName, bgHex] of Object.entries(others)) {
  for (const [stateName, stateHex] of Object.entries(STATES)) {
    const out = C.readableOn(hex(stateHex), hex(bgHex))
    check(stateName + " on " + bgName + " is untouched", out === stateHex, "got " + out)
  }
}

// ---------------------------------------------------------------------------
console.log("\nsweep: 420 backgrounds in each state's own hue family")
for (const [stateName, stateHex] of Object.entries(STATES)) {
  const base = hex(stateHex)
  const hsv = C.rgbToHsv(base)
  let worst = Infinity
  let worstCase = ""
  for (const dh of [-0.08, -0.04, 0, 0.04, 0.08]) {
    for (const sat of [0.25, 0.5, 0.75, 1.0]) {
      for (const val of [0.15, 0.3, 0.45, 0.6, 0.75, 0.9, 1.0]) {
        const bg = C.hsvToRgb((hsv.h + dh + 1) % 1, sat, val)
        const out = C.readableOn(base, bg)
        const d = C.deltaE(hex(out), bg)
        if (d < worst) {
          worst = d
          worstCase = C.toHex(bg) + " -> " + out
        }
      }
    }
  }
  check(
    stateName + " clears the floor on every same-hue background",
    worst >= C.MIN_DISTANCE,
    "worst dE " + worst.toFixed(1) + " (" + worstCase + ")"
  )
}

// ---------------------------------------------------------------------------
console.log("\nedge cases")
check("transparent bar leaves the colour alone",
  C.readableOn(hex("#e05252"), { r: 0, g: 0, b: 0, a: 0 }) === "#e05252")
check("missing background leaves the colour alone",
  C.readableOn(hex("#e05252"), null) === "#e05252")

const outputs = []
for (const [name, value] of Object.entries(STATES)) {
  outputs.push(C.readableOn(hex(value), hex(value)))
  outputs.push(C.readableOn(hex(value), blue))
}
check("every result is a valid #rrggbb",
  outputs.every(o => /^#[0-9a-f]{6}$/.test(o)),
  outputs.join(" "))

check("identical colours have zero distance", C.deltaE(hex("#e05252"), hex("#e05252")) === 0)
check("black on white is 21:1",
  Math.abs(C.contrastRatio(hex("#000000"), hex("#ffffff")) - 21) < 0.01)
check("lighter keeps the hue",
  Math.abs(C.rgbToHsv(C.lighter(hex("#e05252"), 1.6)).h - C.rgbToHsv(hex("#e05252")).h) < 0.01)
check("darker keeps the hue",
  Math.abs(C.rgbToHsv(C.darker(hex("#e05252"), 1.6)).h - C.rgbToHsv(hex("#e05252")).h) < 0.01)

// ---------------------------------------------------------------------------
console.log("\n" + pass + " passed, " + fail + " failed")
if (fail > 0) {
  console.log("failed:")
  for (const name of failures) console.log("  - " + name)
  process.exit(1)
}
