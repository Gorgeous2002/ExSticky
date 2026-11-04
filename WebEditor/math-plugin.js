export default function mathPlugin(md) {
    function closing(source, delimiter, start) {
        let index = start;
        while ((index = source.indexOf(delimiter, index)) !== -1) {
            let slashes = 0;
            for (let i = index - 1; i >= 0 && source[i] === '\\'; i--) slashes++;
            if (slashes % 2 === 0) return index;
            index += delimiter.length;
        }
        return -1;
    }
    md.inline.ruler.before('escape', 'math', function (state, silent) {
        const start = state.pos;
        const rest = state.src.slice(start);
        const open = ['$$', '$'].find(d => rest.startsWith(d));
        if (!open) return false;
        const close = open === '\\(' ? '\\)' : open === '\\[' ? '\\]' : open;
        const begin = start + open.length;
        if (open === '$' && /\s/.test(state.src[begin] || ' ')) return false;
        const end = closing(state.src, close, begin);
        if (end < 0 || end >= state.posMax || end === begin) return false;
        // Avoid interpreting prices such as "$5 and $10" as a formula.
        if (open === '$' && (/\s/.test(state.src[end - 1]) || /\d/.test(state.src[end + 1] || ''))) return false;
        if (!silent) {
            const token = state.push('math_inline', '', 0);
            token.content = state.src.slice(begin, end);
            token.block = open === '$$' || open === '\\[';
        }
        state.pos = end + close.length;
        return true;
    });
    md.block.ruler.before('fence', 'math_block', function (state, start, end, silent) {
        const first = state.src.slice(state.bMarks[start] + state.tShift[start], state.eMarks[start]).trim();
        const open = first.startsWith('$$') ? '$$' : null;
        if (!open) return false;
        const close = open === '$$' ? '$$' : '\\]';
        let content = first.slice(open.length);
        let line = start;
        let index = closing(content, close, 0);
        while (index < 0 && ++line < end) {
            content += '\n' + state.src.slice(state.bMarks[line] + state.tShift[line], state.eMarks[line]);
            index = closing(content, close, 0);
        }
        if (index < 0 || content.slice(index + close.length).trim()) return false;
        if (silent) return true;
        const token = state.push('math_block', '', 0);
        token.block = true;
        token.content = content.slice(0, index).trim();
        token.map = [start, line + 1];
        state.line = line + 1;
        return true;
    }, { alt: ['paragraph', 'reference', 'blockquote', 'list'] });
}
