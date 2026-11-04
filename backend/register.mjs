import { createRequire, registerHooks } from 'node:module';
import { pathToFileURL } from 'node:url';
const require = createRequire(import.meta.url);
const joseUrl = pathToFileURL(require.resolve('jose')).href;
registerHooks({
  resolve(specifier, context, next) {
    if (specifier === 'jose') return next(joseUrl, context);
    return next(specifier, context);
  }
});
