import {readFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';
const sql=readFileSync(new URL('../corvia-ai-nurse/database.sql',import.meta.url),'utf8');
assert.equal((sql.match(/CREATE TABLE /g)||[]).length,8);
assert.ok(!/\b\d{13}\b|@(?:gmail|yahoo|outlook)\.|\+27\d{9}/i.test(sql));
for(const batch of sql.split(/^\s*GO\s*$/mi)){
 const clean=batch.replace(/\/\*[\s\S]*?\*\//g,'').replace(/--[^\n]*/g,'').trim();
 if(/CREATE (?:OR ALTER )?(TRIGGER|PROCEDURE)/i.test(clean))assert.match(clean,/^CREATE (?:OR ALTER )?(TRIGGER|PROCEDURE)/i);
}
console.log('Corvia static SQL checks passed (not a SQL Server execution test).');
const dll=fileURLToPath(new URL('../student-grade-manager/bin/Debug/net10.0/GradeManagementSystem.dll',import.meta.url));
for(const [input,expected] of [
 ['1\n3\n4\n',['No grades available.','No grades available to calculate average.']],
 ['2\n80\n2\n90\n1\n3\n4\n',['Grade 1: 80.00','Grade 2: 90.00','Average Grade: 85.00']],
 ['oops\n2\n-1\n2\n101\n2\nNaN\n2\nInfinity\n2\n75.5\n3\n4\n',['Error: Invalid input.','Average Grade: 75.50']],
 ['', ['Exiting system. Goodbye!']]
]){
 const run=spawnSync('dotnet',[dll],{input,encoding:'utf8',timeout:15000});
 assert.ifError(run.error);assert.equal(run.status,0,run.stderr);
 for(const text of expected)assert.ok(run.stdout.includes(text),`Missing: ${text}`);
}
console.log('Student Grade Manager passed: empty list, average, input bounds, non-finite values and EOF.');
