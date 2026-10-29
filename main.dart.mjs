// Compiles a dart2wasm-generated main module from `source` which can then
// be instantiated via the `instantiate` method.
//
// `source` needs to be a `Response` object (or promise thereof) e.g. created
// via the `fetch()` JS API.
export async function compileStreaming(source) {
  const builtins = {builtins: ['js-string']};
  return new CompiledApp(
      await WebAssembly.compileStreaming(source, builtins), builtins);
}

// Compiles a dart2wasm-generated wasm module from `bytes` which is then
// instantiable via the `instantiate` method.
export async function compile(bytes) {
  const builtins = {builtins: ['js-string']};
  return new CompiledApp(await WebAssembly.compile(bytes, builtins), builtins);
}

class CompiledApp {
  constructor(module, builtins) {
    this.module = module;
    this.builtins = builtins;
  }

  // The second argument is an options object containing:
  // `loadDeferredModules` is a JS function that takes an array of module names
  //   matching wasm files produced by the dart2wasm compiler. It also takes a
  //   callback that should be invoked for each loaded module with 2 arguments:
  //   (1) the module name, (2) the loaded module in a format supported by
  //   `WebAssembly.compile` or `WebAssembly.compileStreaming`. The callback
  //   returns a Promise that resolves when the module is instantiated.
  //   loadDeferredModules should return a Promise that resolves when all the
  //   modules have been loaded and the callback promises have resolved.
  // `loadDeferredId` is a JS function that takes load ID produced by the
  //   compiler when the `use-load-ids` option is passed. Each load ID maps to
  //   one or more wasm files as specified in the emitted JSON file. It also
  //   takes a callback that should be invoked for each loaded module with 2
  //   arguments: (1) the module name, (2) the loaded module in a format
  //   supported by `WebAssembly.compile` or `WebAssembly.compileStreaming`.
  //   The callback returns a Promise that resolves when the module is
  //   instantiated.
  //   loadDeferredId should return a Promise that resolves when all the
  //   modules have been loaded and the callback promises have resolved.
  async instantiate(additionalImports, {loadDeferredModules, loadDeferredId} = {}) {
    let dartInstance;

    // Prints to the console
    function printToConsole(value) {
      if (typeof dartPrint == "function") {
        dartPrint(value);
        return;
      }
      if (typeof console == "object" && typeof console.log != "undefined") {
        console.log(value);
        return;
      }
      if (typeof print == "function") {
        print(value);
        return;
      }

      throw "Unable to print message: " + value;
    }

    // A special symbol attached to functions that wrap Dart functions.
    const jsWrappedDartFunctionSymbol = Symbol("JSWrappedDartFunction");

    function finalizeWrapper(dartFunction, wrapped) {
      wrapped.dartFunction = dartFunction;
      wrapped[jsWrappedDartFunctionSymbol] = true;
      return wrapped;
    }

    // Imports
    const dart2wasm = {
            AB: o => {
        if (o === undefined || o === null) return 0;
        if (typeof o === 'boolean') return 1;
        return 2;
      },
      AC: Function.prototype.call.bind(DataView.prototype.setInt32),
      AD: x0 => x0.maxTouchPoints,
      AE: x0 => x0.nonce,
      AF: (x0,x1) => x0.removeAttribute(x1),
      AG: x0 => x0.offsetX,
      AH: x0 => x0.clientHeight,
      AI: (x0,x1) => { x0.min = x1 },
      B: s => printToConsole(s),
      BB: x0 => x0.flags,
      BC: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Int32Array) return 1;
        return 2;
      },
      BD: x0 => x0.platform,
      BE: () => globalThis.window.flutterConfiguration,
      BF: x0 => x0.isConnected,
      BG: x0 => x0.type,
      BH: x0 => x0.innerWidth,
      BI: (x0,x1) => { x0.max = x1 },
      C: Function.prototype.call.bind(Number.prototype.toString),
      CB: (s, m) => {
        try {
          return new RegExp(s, m);
        } catch (e) {
          return String(e);
        }
      },
      CC: o => o instanceof Uint16Array,
      CD: x0 => x0.navigator,
      CE: (x0,x1) => x0.attachShadow(x1),
      CF: x0 => x0.click(),
      CG: x0 => x0.hasFocus(),
      CH: x0 => x0.width,
      CI: (x0,x1) => { x0.disabled = x1 },
      D: Function.prototype.call.bind(BigInt.prototype.toString),
      DB: o => o instanceof RegExp,
      DC: Function.prototype.call.bind(DataView.prototype.getUint16),
      DD: s => new Date(s * 1000).getTimezoneOffset() * 60,
      DE: x0 => x0.preventDefault(),
      DF: (x0,x1) => x0.getElementsByClassName(x1),
      DG: x0 => x0.shiftKey,
      DH: x0 => x0.clientWidth,
      DI: (x0,x1) => { x0.scrollLeft = x1 },
      E: (exn) => {
        let stackString = exn.toString();
        let frames = stackString.split('\n');
        let drop = 4;
        if (frames[0].startsWith('Error')) {
            drop += 1;
        }
        return frames.slice(drop).join('\n');
      },
      EB: (a, i, v) => a[i] = v,
      EC: Function.prototype.call.bind(DataView.prototype.setUint16),
      ED: Date.now,
      EE: (x0,x1) => x0.contains(x1),
      EF: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmF32ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      EG: x0 => x0.visibilityState,
      EH: (x0,x1) => x0.removeChild(x1),
      EI: (x0,x1) => { x0.spellcheck = x1 },
      F: () => new Error().stack,
      FB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI8ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      FC: o => o instanceof Int16Array,
      FD: (x0,x1,x2) => x0.setAttribute(x1,x2),
      FE: (x0,x1) => x0.focus(x1),
      FF: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmF64ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      FG: x0 => x0.disconnect(),
      FH: x0 => x0.firstChild,
      FI: (x0,x1) => { x0.disabled = x1 },
      G: s => JSON.stringify(s),
      GB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI16ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      GC: Function.prototype.call.bind(DataView.prototype.getInt16),
      GD: (x0,x1,x2,x3) => x0.setProperty(x1,x2,x3),
      GE: (x0,x1) => x0.closest(x1),
      GF: (x0,x1) => x0.contains(x1),
      GG: x0 => new Intl.Locale(x0),
      GH: x0 => x0.viewConstraints,
      GI: (a, i) => a.splice(i, 1),
      H: Function.prototype.call.bind(Number.prototype.toString),
      HB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI32ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      HC: Function.prototype.call.bind(DataView.prototype.setInt16),
      HD: x0 => x0.style,
      HE: (x0,x1) => x0.getAttribute(x1),
      HF: (s) => +s,
      HG: x0 => x0.region,
      HH: x0 => x0.hostElement,
      HI: a => a.pop(),
      I: Function.prototype.call.bind(String.prototype.indexOf),
      IB: Function.prototype.call.bind(String.prototype.toLowerCase),
      IC: o => o instanceof Uint8ClampedArray,
      ID: (x0,x1) => x0.createElement(x1),
      IE: x0 => x0.activeElement,
      IF: x0 => x0.target,
      IG: x0 => x0.script,
      IH: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      II: (map, o, v) => map.set(o, v),
      J: (s, p, i) => s.lastIndexOf(p, i),
      JB: (x0,x1,x2,x3) => x0.pushState(x1,x2,x3),
      JC: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Uint8Array) return 1;
        return 2;
      },
      JD: x0 => x0.body,
      JE: (x0,x1) => x0.add(x1),
      JF: (x0,x1) => x0.dispatchEvent(x1),
      JG: x0 => x0.language,
      JH: x0 => ({runApp: x0}),
      JI: (map, o) => map.get(o),
      K: (exn) => {
        if (exn instanceof Error) {
          return exn.stack;
        } else {
          return null;
        }
      },
      KB: () => ({}),
      KC: Function.prototype.call.bind(DataView.prototype.setInt8),
      KD: x0 => x0.remove(),
      KE: x0 => x0.classList,
      KF: (x0,x1) => x0.createEvent(x1),
      KG: x0 => x0.languages,
      KH: Function.prototype.call.bind(DataView.prototype.setBigInt64),
      KI: () => new WeakMap(),
      L: o => o === undefined,
      LB: (o, p, v) => o[p] = v,
      LC: Function.prototype.call.bind(DataView.prototype.getInt8),
      LD: (x0,x1) => x0.getPropertyValue(x1),
      LE: x0 => x0.data,
      LF: (x0,x1,x2,x3) => x0.initEvent(x1,x2,x3),
      LG: (x0,x1) => x0.observe(x1),
      LH: Function.prototype.call.bind(DataView.prototype.getBigInt64),
      LI: x0 => new WeakRef(x0),
      M: o => String(o),
      MB: () => [],
      MC: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Int8Array) return 1;
        return 2;
      },
      MD: (x0,x1) => x0.warn(x1),
      ME: x0 => x0.scrollTop,
      MF: () => globalThis.window,
      MG: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      MH: (o, start, length) => new BigInt64Array(o.buffer, o.byteOffset + start, length),
      MI: x0 => x0.deref(),
      N: (c) =>
      queueMicrotask(() => dartInstance.exports.$invokeCallback(c)),
      NB: (a, i) => a.push(i),
      NC: (o, start, length) => new Float64Array(o.buffer, o.byteOffset + start, length),
      ND: x0 => x0.console,
      NE: (handle) => clearTimeout(handle),
      NF: x0 => x0.readText(),
      NG: x0 => new ResizeObserver(x0),
      NH: () => typeof dartUseDateNowForTicks !== "undefined",
      NI: () => globalThis.WeakRef,
      O: (x0,x1) => x0.didCreateEngineInitializer(x1),
      OB: b => !!b,
      OC: (o, start, length) => new Float32Array(o.buffer, o.byteOffset + start, length),
      OD: (x0,x1) => { x0.id = x1 },
      OE: (x0,x1) => { x0.scrollTop = x1 },
      OF: x0 => x0.clipboard,
      OG: x0 => globalThis.parseFloat(x0),
      OH: () => Date.now(),
      OI: (o, offsetInBytes, lengthInBytes) => {
        var dst = new ArrayBuffer(lengthInBytes);
        new Uint8Array(dst).set(new Uint8Array(o, offsetInBytes, lengthInBytes));
        return new DataView(dst);
      },
      P: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      PB: x0 => new Int8Array(x0),
      PC: (o, start, length) => new Uint32Array(o.buffer, o.byteOffset + start, length),
      PD: s => s.trimLeft(),
      PE: x0 => x0.tagName,
      PF: (x0,x1) => x0.writeText(x1),
      PG: (x0,x1) => x0.getComputedStyle(x1),
      PH: () => 1000 * performance.now(),
      PI: (a, s, e) => a.slice(s, e),
      Q: (wasmFunction,f) => finalizeWrapper(f, function() { return wasmFunction(f,arguments.length) }),
      QB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI8ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      QC: (o, start, length) => new Int32Array(o.buffer, o.byteOffset + start, length),
      QD: (o, p, r) => o.replaceAll(p, () => r),
      QE: (x0,x1,x2) => x0.setSelectionRange(x1,x2),
      QF: x0 => x0.unlock(),
      QG: x0 => x0.documentElement,
      QH: x0 => new Uint8Array(x0),
      QI: (x0,x1) => x0.transferFromImageBitmap(x1),
      R: (x0,x1) => ({initializeEngine: x0,autoStart: x1}),
      RB: x0 => new Uint8Array(x0),
      RC: (o, start, length) => new Uint16Array(o.buffer, o.byteOffset + start, length),
      RD: (x0,x1) => x0[x1],
      RE: (x0,x1) => { x0.value = x1 },
      RF: (x0,x1) => x0.lock(x1),
      RG: x0 => x0.computedStyleMap(),
      RH: (x0,x1,x2) => x0.slice(x1,x2),
      RI: (x0,x1) => x0.getContext(x1),
      S: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      SB: x0 => new Uint8ClampedArray(x0),
      SC: (o, start, length) => new Int16Array(o.buffer, o.byteOffset + start, length),
      SD: x0 => x0.length,
      SE: (x0,x1,x2) => x0.setSelectionRange(x1,x2),
      SF: x0 => x0.orientation,
      SG: (x0,x1) => x0.get(x1),
      SH: (x0,x1) => x0.decode(x1),
      SI: (x0,x1) => { x0.height = x1 },
      T: x0 => new Promise(x0),
      TB: x0 => new Int16Array(x0),
      TC: (o, start, length) => new Uint8ClampedArray(o.buffer, o.byteOffset + start, length),
      TD: (x0,x1) => x0.exec(x1),
      TE: (x0,x1) => { x0.value = x1 },
      TF: (x0,x1) => x0.querySelector(x1),
      TG: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      TH: (x0,x1) => x0.adoptText(x1),
      TI: (x0,x1) => { x0.width = x1 },
      U: (x0,x1,x2) => x0.call(x1,x2),
      UB: x0 => new Uint16Array(x0),
      UC: (o, start, length) => new Int8Array(o.buffer, o.byteOffset + start, length),
      UD: s => s.trim(),
      UE: x0 => x0.relatedTarget,
      UF: (x0,x1) => { x0.content = x1 },
      UG: x0 => x0.matches,
      UH: x0 => x0.first(),
      UI: x0 => x0.height,
      V: (constructor, args) => {
        const factoryFunction = constructor.bind.apply(
            constructor, [null, ...args]);
        return new factoryFunction();
      },
      VB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI16ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      VC: x0 => x0.history,
      VD: (a, s) => a.join(s),
      VE: x0 => x0.index,
      VF: x0 => x0.head,
      VG: (x0,x1) => x0.matchMedia(x1),
      VH: x0 => x0.next(),
      VI: x0 => x0.width,
      W: x0 => new Array(x0),
      WB: x0 => new Int32Array(x0),
      WC: x0 => x0.search,
      WD: (x0,x1) => x0.error(x1),
      WE: x0 => x0.unicode,
      WF: (x0,x1) => { x0.name = x1 },
      WG: x0 => x0.matches,
      WH: x0 => x0.current(),
      WI: x0 => x0.rasterEndMilliseconds,
      X: o => [o],
      XB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI32ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      XC: o => {
        if (o === null || o === undefined) return 0;
        if (typeof(o) === 'string') return 1;
        return 2;
      },
      XD: () => globalThis.console,
      XE: (x0,x1) => { x0.lastIndex = x1 },
      XF: (x0,x1) => { x0.title = x1 },
      XG: x0 => x0.timeStamp,
      XH: (x0,x1) => new Intl.v8BreakIterator(x0,x1),
      XI: x0 => x0.rasterStartMilliseconds,
      Y: (o0, o1) => [o0, o1],
      YB: x0 => new Uint32Array(x0),
      YC: x0 => x0.location,
      YD: s => s.trimRight(),
      YE: x0 => x0.dotAll,
      YF: () => globalThis.document,
      YG: (x0,x1) => x0.hasAttribute(x1),
      YH: x0 => x0.v8BreakIterator,
      YI: x0 => x0.imageBitmaps,
      Z: (o0, o1, o2) => [o0, o1, o2],
      ZB: x0 => new Float32Array(x0),
      ZC: x0 => x0.pathname,
      ZD: (x0,x1) => x0.requestAnimationFrame(x1),
      ZE: x0 => x0.ignoreCase,
      ZF: (x0,x1) => x0.vibrate(x1),
      ZG: x0 => x0.buttons,
      ZH: () => globalThis.Intl,
      ZI: x0 => x0.canvasKitMaximumSurfaces,
      a: (o0, o1, o2, o3) => [o0, o1, o2, o3],
      aB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmF32ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      aC: (x0,x1,x2,x3) => x0.replaceState(x1,x2,x3),
      aD: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      aE: x0 => x0.multiline,
      aF: (o, p) => p in o,
      aG: x0 => x0.ctrlKey,
      aH: (x0,x1) => x0.segment(x1),
      aI: x0 => x0.hostElement,
      b: (x0,x1,x2) => { x0[x1] = x2 },
      bB: x0 => new Float64Array(x0),
      bC: o => {
        const proto = Object.getPrototypeOf(o);
        return proto === Object.prototype || proto === null;
      },
      bD: x0 => x0.now(),
      bE: s => {
        if (/[[\]{}()*+?.\\^$|]/.test(s)) {
            s = s.replace(/[[\]{}()*+?.\\^$|]/g, '\\$&');
        }
        return s;
      },
      bF: x0 => x0.arrayBuffer(),
      bG: x0 => x0.y,
      bH: x0 => x0.index,
      bI: x0 => x0.location,
      c: o => o,
      cB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmF64ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      cC: o => Object.keys(o),
      cD: x0 => x0.performance,
      cE: x0 => x0.value,
      cF: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof ArrayBuffer) return 1;
        if (globalThis.SharedArrayBuffer !== undefined &&
            o instanceof SharedArrayBuffer) {
          return 2;
        }
        return 3;
      },
      cG: x0 => x0.x,
      cH: x0 => x0.next(),
      cI: (x0,x1) => x0.getModifierState(x1),
      d: (o, p) => o[p],
      dB: x0 => new ArrayBuffer(x0),
      dC: o => typeof o === 'function' && o[jsWrappedDartFunctionSymbol] === true,
      dD: (x0,x1) => x0.unregister(x1),
      dE: x0 => x0.selectionDirection,
      dF: x0 => x0.status,
      dG: x0 => x0.offsetTop,
      dH: x0 => x0.value,
      dI: x0 => x0.metaKey,
      e: () => globalThis,
      eB: (x0,x1,x2) => new Uint8Array(x0,x1,x2),
      eC: f => f.dartFunction,
      eD: () => globalThis.window.FinalizationRegistry,
      eE: x0 => x0.selectionStart,
      eF: (x0,x1) => x0.fetch(x1),
      eG: x0 => x0.scrollLeft,
      eH: x0 => x0.done,
      eI: x0 => x0.altKey,
      f: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      fB: (x0,x1,x2) => new DataView(x0,x1,x2),
      fC: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      fD: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      fE: x0 => x0.selectionEnd,
      fF: x0 => x0.content,
      fG: x0 => x0.offsetLeft,
      fH: (o, m, a) => o[m].apply(o, a),
      fI: x0 => x0.ctrlKey,
      g: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      gB: (o, p) => o[p],
      gC: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      gD: x0 => new window.FinalizationRegistry(x0),
      gE: x0 => x0.value,
      gF: x0 => x0.document,
      gG: x0 => x0.offsetParent,
      gH: x0 => x0.iterator,
      gI: x0 => x0.isComposing,
      h: (x0,x1) => ({addView: x0,removeView: x1}),
      hB: (o) => new DataView(o.buffer, o.byteOffset, o.byteLength),
      hC: (p, s, f) => p.then(s, (e) => f(e, e === undefined)),
      hD: x0 => x0.scale,
      hE: x0 => x0.selectionDirection,
      hF: x0 => x0.language,
      hG: x0 => x0.deltaMode,
      hH: () => globalThis.Symbol,
      hI: x0 => x0.code,
      i: (l, r) => l === r,
      iB: Function.prototype.call.bind(Object.getOwnPropertyDescriptor(DataView.prototype, 'byteLength').get),
      iC: (o, i) => o[i],
      iD: x0 => x0.visualViewport,
      iE: x0 => x0.selectionStart,
      iF: (x0,x1,x2,x3) => x0.register(x1,x2,x3),
      iG: x0 => x0.deltaY,
      iH: (x0,x1) => new Intl.Segmenter(x0,x1),
      iI: x0 => x0.repeat,
      j: (string, token) => string.split(token),
      jB: Function.prototype.call.bind(DataView.prototype.setFloat64),
      jC: o => o.length,
      jD: x0 => x0.devicePixelRatio,
      jE: x0 => x0.selectionEnd,
      jF: (x0,x1) => x0.prepend(x1),
      jG: x0 => x0.deltaX,
      jH: x0 => x0.Segmenter,
      jI: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      k: o => o instanceof Array,
      kB: o => o.byteOffset,
      kC: o => {
        if (o === undefined) return 1;
        var type = typeof o;
        if (type === 'boolean') return 2;
        if (type === 'number') return 3;
        if (type === 'string') return 4;
        if (o instanceof Array) return 5;
        if (ArrayBuffer.isView(o)) {
          if (o instanceof Int8Array) return 6;
          if (o instanceof Uint8Array) return 7;
          if (o instanceof Uint8ClampedArray) return 8;
          if (o instanceof Int16Array) return 9;
          if (o instanceof Uint16Array) return 10;
          if (o instanceof Int32Array) return 11;
          if (o instanceof Uint32Array) return 12;
          if (o instanceof Float32Array) return 13;
          if (o instanceof Float64Array) return 14;
          if (o instanceof DataView) return 15;
        }
        if (o instanceof ArrayBuffer) return 16;
        // Feature check for `SharedArrayBuffer` before doing a type-check.
        if (globalThis.SharedArrayBuffer !== undefined &&
            o instanceof SharedArrayBuffer) {
            return 17;
        }
        if (o instanceof Promise) return 18;
        return 19;
      },
      kD: (d, digits) => d.toFixed(digits),
      kE: x0 => x0.keyCode,
      kF: (x0,x1,x2,x3) => x0.addEventListener(x1,x2,x3),
      kG: x0 => x0.wheelDeltaY,
      kH: x0 => x0.buffer,
      kI: x0 => x0.length,
      l: (a, i) => a[i],
      lB: o => o.buffer,
      lC: x0 => x0.state,
      lD: x0 => x0.maxHeight,
      lE: (x0,x1) => x0.scrollIntoView(x1),
      lF: (x0,x1) => x0.querySelector(x1),
      lG: x0 => x0.wheelDeltaX,
      lH: x0 => x0.wasmMemory,
      lI: x0 => x0.getReader(),
      m: a => a.length,
      mB: (b, o) => new DataView(b, o),
      mC: x0 => x0.hash,
      mD: x0 => x0.maxWidth,
      mE: x0 => x0.multiViewEnabled,
      mF: (x0,x1) => x0.querySelectorAll(x1),
      mG: x0 => x0.key,
      mH: () => globalThis.window._flutter_skwasmInstance,
      mI: x0 => x0.value,
      n: (string, times) => string.repeat(times),
      nB: (b, o, l) => new DataView(b, o, l),
      nC: (x0,x1,x2) => x0.removeEventListener(x1,x2),
      nD: x0 => x0.minHeight,
      nE: x0 => x0.parent,
      nF: x0 => x0.tabIndex,
      nG: x0 => x0.identifier,
      nH: () => new TextDecoder(),
      nI: x0 => x0.done,
      o: (decoder, codeUnits) => decoder.decode(codeUnits),
      oB: Function.prototype.call.bind(DataView.prototype.getUint8),
      oC: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      oD: x0 => x0.minWidth,
      oE: (x0,x1) => x0.replaceWith(x1),
      oF: x0 => x0.parentNode,
      oG: x0 => x0.touches,
      oH: x0 => x0.debugSkipFontRetryDelay,
      oI: x0 => x0.read(),
      p: (o, start, length) => new Uint8Array(o.buffer, o.byteOffset + start, length),
      pB: Function.prototype.call.bind(DataView.prototype.setUint8),
      pC: x0 => x0.state,
      pD: x0 => x0.height,
      pE: (x0,x1) => { x0.type = x1 },
      pF: x0 => x0.clientY,
      pG: x0 => x0.pressure,
      pH: (x0,x1,x2) => x0.set(x1,x2),
      pI: x0 => x0.body,
      q: () => new TextDecoder("utf-8", {fatal: true}),
      qB: Function.prototype.call.bind(DataView.prototype.getFloat64),
      qC: (x0,x1,x2) => x0.addEventListener(x1,x2),
      qD: x0 => x0.width,
      qE: (x0,x1) => { x0.className = x1 },
      qF: x0 => x0.clientX,
      qG: x0 => x0.tiltY,
      qH: x0 => x0.fontFallbackBaseUrl,
      qI: (x0,x1) => new OffscreenCanvas(x0,x1),
      r: () => new TextDecoder("utf-8", {fatal: false}),
      rB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Float64Array) return 1;
        return 2;
      },
      rC: (x0,x1) => x0.go(x1),
      rD: x0 => x0.screen,
      rE: (x0,x1) => { x0.tabIndex = x1 },
      rF: x0 => x0.getBoundingClientRect(),
      rG: x0 => x0.tiltX,
      rH: (handle) => clearInterval(handle),
      rI: x0 => x0.assetBase,
      s: x0 => x0.random(),
      sB: (t, s) => t.set(s),
      sC: (x0,x1) => x0.append(x1),
      sD: s => {
        if (!/^\s*[+-]?(?:Infinity|NaN|(?:\.\d+|\d+(?:\.\d*)?)(?:[eE][+-]?\d+)?)\s*$/.test(s)) {
          return NaN;
        }
        return parseFloat(s);
      },
      sE: (x0,x1) => { x0.name = x1 },
      sF: x0 => x0.bottom,
      sG: x0 => x0.pointerType,
      sH: (ms, c) =>
      setInterval(() => dartInstance.exports.$invokeCallback(c), ms),
      sI: x0 => x0.loader,
      t: o => o,
      tB: Function.prototype.call.bind(DataView.prototype.setFloat32),
      tC: (x0,x1) => { x0.textContent = x1 },
      tD: (x0,x1) => x0.removeProperty(x1),
      tE: (x0,x1) => { x0.placeholder = x1 },
      tF: x0 => x0.top,
      tG: x0 => x0.pointerId,
      tH: () => Date.now(),
      tI: () => globalThis._flutter,
      u: o => {
        if (o === undefined || o === null) return 0;
        if (typeof o === 'number') return 1;
        return 2;
      },
      uB: Function.prototype.call.bind(DataView.prototype.getFloat32),
      uC: (ms, c) =>
      setTimeout(() => dartInstance.exports.$invokeCallback(c),ms),
      uD: (x0,x1) => x0.appendChild(x1),
      uE: (x0,x1) => { x0.autocomplete = x1 },
      uF: x0 => x0.right,
      uG: x0 => x0.getCoalescedEvents(),
      uH: (x0,x1,x2) => x0.insertBefore(x1,x2),
      v: () => globalThis.Math,
      vB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Float32Array) return 1;
        return 2;
      },
      vC: x0 => x0.parentElement,
      vD: x0 => x0.debugShowSemanticsNodes,
      vE: (x0,x1) => { x0.name = x1 },
      vF: x0 => x0.left,
      vG: (x0,x1) => x0.getModifierState(x1),
      vH: x0 => x0.id,
      w: s => s.toUpperCase(),
      wB: Function.prototype.call.bind(DataView.prototype.getUint32),
      wC: (x0,x1) => x0.querySelectorAll(x1),
      wD: (o, c) => o instanceof c,
      wE: (x0,x1) => { x0.placeholder = x1 },
      wF: x0 => x0.clientY,
      wG: x0 => x0.blur(),
      wH: x0 => x0.offsetHeight,
      x: Object.is,
      xB: Function.prototype.call.bind(DataView.prototype.setUint32),
      xC: x0 => x0.length,
      xD: x0 => x0.vendor,
      xE: (x0,x1) => { x0.action = x1 },
      xF: x0 => x0.clientX,
      xG: x0 => x0.button,
      xH: x0 => x0.offsetWidth,
      y: (x0,x1) => x0.test(x1),
      yB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Uint32Array) return 1;
        return 2;
      },
      yC: (x0,x1) => x0.item(x1),
      yD: (x0,x1) => x0.createTextNode(x1),
      yE: (x0,x1) => { x0.method = x1 },
      yF: x0 => x0.changedTouches,
      yG: x0 => x0.innerHeight,
      yH: x0 => x0.stopPropagation(),
      z: o => o,
      zB: Function.prototype.call.bind(DataView.prototype.getInt32),
      zC: x0 => x0.userAgent,
      zD: (x0,x1) => { x0.nonce = x1 },
      zE: (x0,x1) => { x0.noValidate = x1 },
      zF: x0 => x0.offsetY,
      zG: x0 => x0.height,
      zH: x0 => x0.disabled,

    };

    const baseImports = {
      _: dart2wasm,
      Math: Math,
      Date: Date,
      Object: Object,
      Array: Array,
      Reflect: Reflect,
      WebAssembly: {
        JSTag: WebAssembly.JSTag,
      },
      "": new Proxy({}, { get(_, prop) { return prop; } }),

    };

    const jsStringPolyfill = {
      "charCodeAt": (s, i) => s.charCodeAt(i),
      "compare": (s1, s2) => {
        if (s1 < s2) return -1;
        if (s1 > s2) return 1;
        return 0;
      },
      "concat": (s1, s2) => s1 + s2,
      "equals": (s1, s2) => s1 === s2,
      "fromCharCode": (i) => String.fromCharCode(i),
      "length": (s) => s.length,
      "substring": (s, a, b) => s.substring(a, b),
      "fromCharCodeArray": (a, start, end) => {
        if (end <= start) return '';

        const read = dartInstance.exports.$wasmI16ArrayGet;
        let result = '';
        let index = start;
        const chunkLength = Math.min(end - index, 500);
        let array = new Array(chunkLength);
        while (index < end) {
          const newChunkLength = Math.min(end - index, 500);
          for (let i = 0; i < newChunkLength; i++) {
            array[i] = read(a, index++);
          }
          if (newChunkLength < chunkLength) {
            array = array.slice(0, newChunkLength);
          }
          result += String.fromCharCode(...array);
        }
        return result;
      },
      "intoCharCodeArray": (s, a, start) => {
        if (s === '') return 0;

        const write = dartInstance.exports.$wasmI16ArraySet;
        for (var i = 0; i < s.length; ++i) {
          write(a, start++, s.charCodeAt(i));
        }
        return s.length;
      },
      "test": (s) => typeof s == "string",
    };


    

    dartInstance = await WebAssembly.instantiate(this.module, {
      ...baseImports,
      ...additionalImports,
      
      "wasm:js-string": jsStringPolyfill,
    });

    return new InstantiatedApp(this, dartInstance);
  }
}

class InstantiatedApp {
  constructor(compiledApp, instantiatedModule) {
    this.compiledApp = compiledApp;
    this.instantiatedModule = instantiatedModule;
  }

  // Call the main function with the given arguments.
  invokeMain(...args) {
    this.instantiatedModule.exports.$invokeMain(args);
  }
}
