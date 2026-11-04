const assert = require('node:assert/strict');
const { JSDOM } = require('jsdom');
const esbuild = require('esbuild');
const vm = require('node:vm');
const dom = new JSDOM('<!doctype html><main id="host"></main><section id="math-editor" hidden></section>', { pretendToBeVisual: true });
for (const key of ['window', 'document', 'navigator', 'Node', 'HTMLElement', 'MutationObserver', 'getComputedStyle']) {
    Object.defineProperty(globalThis, key, { value: dom.window[key], configurable: true });
}
dom.window.Range.prototype.getClientRects = () => [];
dom.window.Range.prototype.getBoundingClientRect = () => ({ left: 0, right: 0, top: 0, bottom: 0 });
global.requestAnimationFrame = dom.window.requestAnimationFrame.bind(dom.window);
global.cancelAnimationFrame = dom.window.cancelAnimationFrame.bind(dom.window);
const built = esbuild.buildSync({ entryPoints: [__dirname + '/editor.js'], bundle: true, platform: 'node', format: 'cjs', write: false });
const mod = { exports: {} };
vm.runInThisContext('(function(require,module,exports){' + built.outputFiles[0].text + '\n})')(require, mod, mod.exports);
const { parser, serializer, createEditor } = mod.exports;
const fixtures = [
    '1. 一级\n   1. 二级\n      1. 三级\n      2. 三级乙\n   2. 二级乙\n2. 一级乙',
    '# 标题😀\n\n**粗体**和*斜体*，`code`\n\n> 引用\n\n- 无序列表',
    '公式 $x_i^2 + \\frac{1}{2}$\n\n$$\n\\begin{matrix}a & b \\\\ c & d\\end{matrix}\n$$',
    '```tex\n$x_i$\n```\n\n价格 \\$5 和 \\$10\n\n\\(x_1\\)\n\n\\[\nx^2\n\\]',
    '<script>alert(1)</script>\n\n[bad](javascript:alert(1))\n\n中文\n下一行'
];
for (const source of fixtures) {
    const doc = parser.parse(source);
    assert.deepEqual(parser.parse(serializer.serialize(doc)).toJSON(), doc.toJSON(), source);
}
let changes = [];
window.webkit = { messageHandlers: { markdownChanged: { postMessage: s => changes.push(s) } } };
const view = createEditor(document.getElementById('host'));
function type(text) {
    for (const ch of text) {
        const { from, to } = view.state.selection;
        const handled = view.someProp('handleTextInput', f => f(view, from, to, ch));
        if (!handled) view.dispatch(view.state.tr.insertText(ch));
    }
}
function key(name, extra = {}) {
    return view.someProp('handleKeyDown', f => f(view, new window.KeyboardEvent('keydown', { key: name, ...extra })));
}
type('1. ');
assert.equal(view.state.doc.firstChild.type.name, 'ordered_list');
type('一级'); key('Enter'); type('二级'); key('Tab');
assert.equal(document.querySelectorAll('ol ol').length, 1);
key('Enter'); type('三级'); key('Tab');
assert.equal(document.querySelectorAll('ol ol ol').length, 1);
key('Enter'); type('三级乙');
assert.equal(document.querySelector('ol ol ol').children.length, 2);
key('Tab', { shiftKey: true });
assert.equal(document.querySelector('ol ol').children.length, 2);
const before = serializer.serialize(view.state.doc);
window.setMarkdown(before);
assert.equal(serializer.serialize(view.state.doc), before);
window.editorCommand('undo');
assert.notEqual(serializer.serialize(view.state.doc), before);
window.editorCommand('redo');
assert.equal(serializer.serialize(view.state.doc), before);
window.setMarkdown(''); type('$x_i^2$');
assert.equal(view.state.doc.firstChild.firstChild.type.name, 'math_inline');
assert.ok(document.querySelector('.katex'));
window.setMarkdown(''); type('$5 and $10');
assert.equal(view.state.doc.firstChild.textContent, '$5 and $10');
assert.equal(view.state.doc.firstChild.childCount, 1);
window.setMarkdown(''); type('$$x^2$$');
assert.equal(view.state.doc.firstChild.type.name, 'math_block');
window.setMarkdown('1. first\n2. second');
window.editorCommand('moveDown');
assert.equal(view.state.doc.firstChild.firstChild.textContent, 'second');
window.editorCommand('moveUp');
assert.equal(view.state.doc.firstChild.firstChild.textContent, 'first');
window.setMarkdown(''); type('**粗体**');
assert.equal(view.state.doc.firstChild.firstChild.marks[0].type.name, 'strong');
window.setMarkdown(''); type('1. '); key('Backspace');
assert.equal(view.state.doc.firstChild.type.name, 'paragraph');
window.setMarkdown('1. 项目'); key('End'); // Explicit source parsing does not emit a save.
assert.ok(changes.length > 0);
assert.equal(document.querySelectorAll('script').length, 0);
view.destroy();
console.log('PASS: Markdown round trips, live list conversion, three levels, Enter/Tab/outdent, undo/redo, inline/block math, bold, undo input rule.');
