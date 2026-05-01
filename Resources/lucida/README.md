# Lucida

A modular downloading tool. Includes code for a small collection of streaming services (does not come with accounts or tokens).

Lucida is made to use few NodeJS dependencies and no system dependencies (...besides `ffmpeg`)

## Usage

```ts
import Lucida from 'lucida'
import Tidal from 'lucida/streamers/tidal/main.js'
import Qobuz from 'lucida/streamers/qobuz/main.js'
import Spotify from 'lucida/streamers/spotify/main.js'

const lucida = new Lucida({
	modules: {
		tidal: new Tidal({
			// tokens
		}),
		qobuz: new Qobuz({
			// tokens
		}),
		spotify: new Spotify({
			// options
		})
		// Any other modules
	},
	logins: {
		qobuz: {
			username: '',
			password: ''
		},
		spotify: {
			username: '',
			password: ''
		}
	}
})

// only needed if using modules which use the logins configuration rather than tokens
await lucida.login()

const track = await lucida.getByUrl('https://tidal.com/browse/track/255207223')

await fs.promises.writeFile('test.flac', (await track.getStream()).stream)

// only needed for modules which create persistent connections (of the built-in modules, this is just Spotify)
await lucida.disconnect()
```

For using a specific module, you can just use the functions built into the `Streamer` interface.

## Project Structure

### src/streamers/{app-name}

#### main.ts

Default export is a class which implements the `Streamer` interface:

```ts
interface Streamer {
	hostnames: string[]
	search(query: string, limit: number): Promise<SearchResults>
	getByUrl(url: string): Promise<GetByUrlResponse>
}
```

They can optionally include a login function in this class which takes a username and password (if supported):

```ts
async login(username: string, password: string): void
```

Options for the app, including tokens (if supported by the given app), are passed to the class's constructor:

```ts
new StreamerApp({ token: 'secret!' })
```

The classes can also include their own custom functions. Any function used by Lucida's app-agnostic code should be defined in the `Streamer` interface for compatibility across multiple apps.

#### parse.ts

Functions for parsing the app's API into the types defined in `src/types.ts`.

#### constants.ts

Constants used by `main.ts`. Secrets should not be defined here (or anywhere else in the project).

### src/index.ts

Wraps all the `Streamer`s using a module system. See the usage section.

### src/types.ts

Types used across the project. The purpose of many of these is to make sure all apps' functions return the same types so the rest of the logic can work across all apps the same.

## Acknowledgements

Lucida is partially inspired by [OrpheusDL](https://github.com/yarrm80s/orpheusdl), a Python program for music archival which can be used similarly to Lucida. Some scripts inside Lucida are modeled after OrpheusDL modules.

## License

Copyright hazycora. Under the Opinionated Queer License.
