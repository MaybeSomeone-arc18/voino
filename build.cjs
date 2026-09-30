const esbuild = require('esbuild');
const fs = require('fs');

const isProd = process.env.NODE_ENV === 'production';
// Public SDK identifier only, never a secret API key. Debug defaults to Test Store.
const rcKey = process.env.REVENUECAT_KEY || 'test_qmRnIaeMCBfYXiEhrdWAcxkCtgU';
if (isProd && (!process.env.REVENUECAT_KEY || rcKey.startsWith('test_'))) {
  console.error('Production requires an explicit platform public SDK key. Test Store builds must not go to app stores.');
  process.exit(1);
}

fs.mkdirSync('dist', { recursive: true });
fs.copyFileSync('index.html', 'dist/index.html');
fs.mkdirSync('dist/src', { recursive: true });
fs.copyFileSync('src/style.css', 'dist/src/style.css');

esbuild.build({
  entryPoints: ['src/app.js'],
  bundle: true,
  outfile: 'dist/src/app.js',
  format: 'esm',
  define: {
    'process.env.REVENUECAT_KEY': JSON.stringify(rcKey),
    'process.env.NODE_ENV': JSON.stringify(process.env.NODE_ENV || 'development')
  }
}).catch(() => process.exit(1));
