import assert from 'node:assert/strict'
import { readFileSync, statSync } from 'node:fs'
import { test } from 'node:test'

const root = new URL('../', import.meta.url)
const readJson = path => JSON.parse(readFileSync(new URL(path, root), 'utf8'))

test('local Project references the shipped catalog with catalog-relative Lua file sources', () => {
    const project = readJson('gams.json')
    assert.deepEqual(project.ui.views['view-ng-node'].config.presets, {
        $ref: 'presets.json#/presets',
    })
    const catalogUrl = new URL('presets.json', root)
    const { presets } = JSON.parse(readFileSync(catalogUrl, 'utf8'))
    assert.ok(Array.isArray(presets) && presets.length > 0)
    for (const preset of presets) {
        assert.equal(typeof preset.name, 'string')
        assert.equal(preset.kind, 'code')
        assert.deepEqual(Object.keys(preset.codePath), ['$file'], preset.name)
        const path = preset.codePath.$file
        assert.equal(typeof path, 'string', preset.name)
        assert.ok(path.startsWith('presets/'), preset.name)
        assert.ok(statSync(new URL(path, catalogUrl)).isFile(), path)
    }
})
