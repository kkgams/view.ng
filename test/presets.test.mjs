import assert from 'node:assert/strict'
import { readFileSync, statSync } from 'node:fs'
import { test } from 'node:test'

const root = new URL('../', import.meta.url)
const readJson = path => JSON.parse(readFileSync(new URL(path, root), 'utf8'))

test('local Project references the shipped preset catalog and Lua modules', () => {
    const project = readJson('gams.json')
    assert.deepEqual(project.ui.views['view-ng-node'].config.presets, {
        $ref: 'presets.json#/presets',
    })
    const { presets } = readJson('presets.json')
    assert.ok(Array.isArray(presets) && presets.length > 0)
    for (const preset of presets) {
        assert.equal(typeof preset.name, 'string')
        assert.equal(preset.kind, 'code')
        assert.ok(preset.codePath.startsWith('presets/'), preset.name)
        assert.ok(statSync(new URL(preset.codePath, root)).isFile(), preset.codePath)
    }
})
