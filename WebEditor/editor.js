import { Schema } from 'prosemirror-model';
import { EditorState, TextSelection } from 'prosemirror-state';
import { EditorView } from 'prosemirror-view';
import { schema as baseSchema, defaultMarkdownParser, defaultMarkdownSerializer, MarkdownParser, MarkdownSerializer } from 'prosemirror-markdown';
import { inputRules, wrappingInputRule, textblockTypeInputRule, InputRule, undoInputRule } from 'prosemirror-inputrules';
import { keymap } from 'prosemirror-keymap';
import { baseKeymap, chainCommands, toggleMark, exitCode } from 'prosemirror-commands';
import { splitListItem, sinkListItem, liftListItem, wrapInList } from 'prosemirror-schema-list';
import { history, undo, redo } from 'prosemirror-history';
import MarkdownIt from 'markdown-it';
import katex from 'katex';
import mathPlugin from './math-plugin';

const mathSpec = inline => ({
    group: inline ? 'inline' : 'block', inline, atom: true,
    attrs: { latex: { default: '' } },
    toDOM: node => [inline ? 'span' : 'div', { 'data-math': node.attrs.latex, class: 'math-node' }, node.attrs.latex],
    parseDOM: [{ tag: (inline ? 'span' : 'div') + '[data-math]', getAttrs: dom => ({ latex: dom.getAttribute('data-math') }) }]
});
let nodes = baseSchema.spec.nodes
    .update('heading', { ...baseSchema.spec.nodes.get('heading'), content: 'inline*' })
    .update('list_item', { ...baseSchema.spec.nodes.get('list_item'), content: 'paragraph block*' })
    .update('image', { ...baseSchema.spec.nodes.get('image'), toDOM: node => ['span', { class: 'image-placeholder' }, node.attrs.alt || node.attrs.src] })
    .append({ math_inline: mathSpec(true), math_block: mathSpec(false) });
export const schema = new Schema({ nodes, marks: baseSchema.spec.marks });
const tokenizer = new MarkdownIt('commonmark', { html: false }).use(mathPlugin);
export const parser = new MarkdownParser(schema, tokenizer, {
    ...defaultMarkdownParser.tokens,
    softbreak: { node: 'hard_break' },
    math_inline: { node: 'math_inline', getAttrs: token => ({ latex: token.content }) },
    math_block: { node: 'math_block', getAttrs: token => ({ latex: token.content }) }
});
export const serializer = new MarkdownSerializer({
    ...defaultMarkdownSerializer.nodes,
    math_inline(state, node) { state.write('$' + node.attrs.latex + '$'); },
    math_block(state, node) { state.write('$$\n' + node.attrs.latex + '\n$$'); state.closeBlock(node); }
}, defaultMarkdownSerializer.marks, { escapeExtraCharacters: /\$/g });

function markRule(pattern, type) {
    return new InputRule(pattern, (state, match, start, end) => {
        const content = match[1];
        const tr = state.tr.insertText(content, start, end).addMark(start, start + content.length, type.create());
        tr.removeStoredMark(type);
        return tr;
    });
}
export function plugins() {
    const n = schema.nodes, m = schema.marks;
    return [
        inputRules({ rules: [
            wrappingInputRule(/^(\d+)\.\s$/, n.ordered_list, match => ({ order: +match[1] }),
                (match, node) => node.childCount + node.attrs.order === +match[1]),
            wrappingInputRule(/^\s*([-+*])\s$/, n.bullet_list),
            wrappingInputRule(/^>\s$/, n.blockquote),
            textblockTypeInputRule(/^(#{1,6})\s$/, n.heading, match => ({ level: match[1].length })),
            textblockTypeInputRule(/^```([\w-]*)\s$/, n.code_block, match => ({ params: match[1] })),
            new InputRule(/^\$\$(.+)\$\$$/, (state, match, start, end) =>
                state.tr.replaceWith(start - 1, end, n.math_block.create({ latex: match[1] }))),
            new InputRule(/(?<!\$)\$([^\s$](?:[^$\n]*[^\s$])?)\$$/, (state, match, start, end) =>
                state.tr.replaceWith(start, end, n.math_inline.create({ latex: match[1] }))),
            markRule(/\*\*([^*]+)\*\*$/, m.strong),
            markRule(/(?<!\*)\*([^*]+)\*$/, m.em),
            markRule(/`([^`]+)`$/, m.code)
        ] }),
        keymap({
            'Enter': splitListItem(n.list_item),
            'Tab': sinkListItem(n.list_item), 'Shift-Tab': liftListItem(n.list_item),
            'Mod-]': sinkListItem(n.list_item), 'Mod-[': liftListItem(n.list_item),
            'Backspace': undoInputRule, 'Mod-z': undo, 'Shift-Mod-z': redo, 'Mod-y': redo,
            'Mod-b': toggleMark(m.strong), 'Mod-i': toggleMark(m.em),
            'Shift-Enter': chainCommands(exitCode, (state, dispatch) => {
                if (dispatch) dispatch(state.tr.replaceSelectionWith(n.hard_break.create()).scrollIntoView());
                return true;
            })
        }), keymap(baseKeymap), history()
    ];
}

function mathView(node, view, getPos) {
    const dom = document.createElement(node.isInline ? 'span' : 'div');
    dom.className = 'math-node';
    dom.contentEditable = 'false';
    dom.setAttribute('aria-label', node.attrs.latex);
    katex.render(node.attrs.latex, dom, { displayMode: !node.isInline, throwOnError: false, trust: false, maxExpand: 1000, maxSize: 20 });
    dom.addEventListener('click', event => {
        event.preventDefault();
        openMathEditor(node, view, getPos);
    });
    return { dom, stopEvent: event => event.type === 'click' };
}
function openMathEditor(node, view, getPos) {
    const panel = document.getElementById('math-editor');
    const input = document.getElementById('math-source');
    const preview = document.getElementById('math-preview');
    input.value = node.attrs.latex;
    panel.hidden = false;
    const render = () => katex.render(input.value, preview, { displayMode: !node.isInline, throwOnError: false, trust: false, maxExpand: 1000, maxSize: 20 });
    input.oninput = render;
    const close = () => { panel.hidden = true; view.focus(); };
    document.getElementById('math-apply').onclick = () => {
        const pos = getPos();
        if (typeof pos === 'number') view.dispatch(view.state.tr.setNodeMarkup(pos, undefined, { latex: input.value }));
        close();
    };
    document.getElementById('math-cancel').onclick = close;
    input.onkeydown = e => {
        if (e.key === 'Escape') { e.preventDefault(); close(); }
        if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) document.getElementById('math-apply').click();
    };
    render(); input.focus();
}

function moveBlock(direction) {
    return (state, dispatch) => {
        const $pos = state.selection.$from;
        let depth = $pos.depth;
        while (depth > 1 && $pos.node(depth).type !== schema.nodes.list_item) depth--;
        if (!depth) return false;
        const parent = $pos.node(depth - 1), index = $pos.index(depth - 1);
        const neighbor = index + direction;
        if (neighbor < 0 || neighbor >= parent.childCount) return false;
        const node = $pos.node(depth), other = parent.child(neighbor);
        const start = $pos.before(depth);
        const offset = state.selection.from - start;
        const from = direction < 0 ? start - other.nodeSize : start;
        const to = direction < 0 ? start + node.nodeSize : start + node.nodeSize + other.nodeSize;
        const tr = state.tr.replaceWith(from, to, direction < 0 ? [node, other] : [other, node]);
        tr.setSelection(TextSelection.near(tr.doc.resolve(from + (direction < 0 ? 0 : other.nodeSize) + offset)));
        if (dispatch) dispatch(tr.scrollIntoView());
        return true;
    };
}

export function createEditor(host) {
    let lastSource = '';
    const view = new EditorView(host, {
        state: EditorState.create({ schema, plugins: plugins() }),
        attributes: { 'aria-label': 'Markdown editor', spellcheck: 'false' },
        nodeViews: { math_inline: mathView, math_block: mathView },
        dispatchTransaction(tr) {
            view.updateState(view.state.apply(tr));
            if (tr.docChanged) {
                lastSource = serializer.serialize(view.state.doc);
                window.webkit?.messageHandlers?.markdownChanged?.postMessage(lastSource);
            }
        },
        handlePaste(view, event) {
            const text = event.clipboardData?.getData('text/plain');
            if (!text) return false;
            // Markdown clipboard content follows the same parser as source mode.
            view.dispatch(view.state.tr.replaceSelection(parser.parse(text).slice(0)).scrollIntoView());
            return true;
        }
    });
    window.getMarkdown = () => lastSource;
    window.setMarkdown = source => {
        if (source === lastSource) return;
        lastSource = source;
        document.getElementById('math-editor').hidden = true;
        view.updateState(EditorState.create({ doc: parser.parse(source), plugins: plugins() }));
    };
    window.editorCommand = name => {
        const commands = { indent: sinkListItem(schema.nodes.list_item), outdent: liftListItem(schema.nodes.list_item), bullet: wrapInList(schema.nodes.bullet_list), moveUp: moveBlock(-1), moveDown: moveBlock(1), undo, redo };
        commands[name]?.(view.state, view.dispatch, view);
        view.focus();
    };
    return view;
}
if (typeof document !== 'undefined' && document.getElementById('content')) {
    createEditor(document.getElementById('content'));
    if (navigator.language.startsWith('zh')) {
        document.getElementById('math-apply').textContent = '应用';
        document.getElementById('math-cancel').textContent = '取消';
        document.getElementById('math-source').setAttribute('aria-label', 'LaTeX 公式');
    }
}
