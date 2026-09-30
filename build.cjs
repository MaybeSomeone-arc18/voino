const esbuild = require('esbuild');
const fs = require('fs');

const isProd = process.env.NODE_ENV === 'production';
const rcKey = process.env.REVENUECAT_KEY || (isProd ? 'PRODUCTION_KEY_OMITTED' : 'goog_test_key_placeholder');

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
