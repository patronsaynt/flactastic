import Lucida, { LucidaOptions } from './index.js'
import { GetByUrlResponse, Streamer } from './types.js'

import fs from 'node:fs'

let testOptions: {
	[module: string]: {
		username?: string
		password?: string
		[key: string]: string | number | boolean | undefined
	}
}

if (!process.env.TEST_OPTIONS) {
	console.error(
		'No test options found in environment variables. Trying to read from .test-options.json'
	)
	try {
		const testOptionsFile = fs.readFileSync('.test-options.json', 'utf-8')
		testOptions = JSON.parse(testOptionsFile)
	} catch (error) {
		console.error(
			'No test options found in environment variables or .test-options.json. Exiting...'
		)
		process.exit(1)
	}
} else testOptions = JSON.parse(process.env.TEST_OPTIONS)

async function start() {
	const lucidaOptions: LucidaOptions = {
		modules: {}
	}

	for (const [module, options] of Object.entries(testOptions)) {
		const username = options.username
		const password = options.password
		delete options.username
		delete options.password
		const { default: Streamer } = await import(`lucida/streamers/${module}`)
		lucidaOptions.modules[module] = <Streamer>new Streamer(options)
		if (username && password) {
			lucidaOptions.logins ??= {}
			lucidaOptions.logins[module] = { username, password }
		}
	}

	const lucida = new Lucida(lucidaOptions)
	await lucida.login(true)

	const testResults: {
		[module: string]: {
			loginSuccess: boolean
			searchSuccess: boolean
			urlTestsSuccess?: number
		}
	} = {}

	for (const moduleName of Object.keys(testOptions)) {
		const module = lucida.modules[moduleName]
		console.log(`Testing ${moduleName}...`)
		testResults[moduleName] ??= {
			loginSuccess: module ? true : false,
			searchSuccess: false
		}
		if (!module) {
			console.error(`Module ${moduleName} not found in Lucida instance. Skipping...`)
			continue
		}
		try {
			await Promise.race([
				module.search('test', 5),
				new Promise((_, reject) => setTimeout(() => reject('Search timed out'), 10000))
			])
			console.log(`Searching with the ${moduleName} streamer succeeded`)
			testResults[moduleName].searchSuccess = true
		} catch (error) {
			console.error(`Searching with the ${moduleName} streamer failed:`, error)
		}

		let urlTestsSuccess = 0
		if (module.testData) {
			for (const url in module.testData) {
				const expected = module.testData[url]
				let getResult: GetByUrlResponse
				try {
					getResult = <GetByUrlResponse>(
						await Promise.race([
							module.getByUrl(url),
							new Promise((_, reject) => setTimeout(() => reject('Search timed out'), 10000))
						])
					)
				} catch (error) {
					console.error(`Getting data from ${url} with the ${moduleName} streamer failed:`, error)
					continue
				}
				const actual = {
					title: getResult.type != 'artist' ? getResult.metadata.title : getResult.metadata.name,
					type: getResult.type
				}
				const success = {
					title: actual.title.toLowerCase() == expected.title.toLowerCase(),
					type: actual.type == expected.type
				}
				if (!success.type) {
					console.error(
						`Type mismatch for ${url} with the ${moduleName} streamer. Expected: ${expected.title}, got: ${actual.title}`
					)
				}
				if (!success.title) {
					console.error(
						`Title mismatch for ${url} with the ${moduleName} streamer. Expected: ${expected.title}, got: ${actual.title}`
					)
				}
				if (success.title && success.type) {
					console.log(`getByUrl test succeeded`)
					urlTestsSuccess++
				}
			}

			testResults[moduleName].urlTestsSuccess =
				urlTestsSuccess / Object.keys(module.testData).length
		} else {
			console.error(`No test data found for ${moduleName}. Skipping URL tests...`)
		}
	}

	lucida.disconnect()

	console.log('Testing complete. Results:', testResults)

	const readableResults = Object.entries(testResults).map((result) => {
		const moduleName = result[0]
		const moduleResults = result[1]
		const score = Object.values(moduleResults).filter(
			(result) => result === 1 || result != false
		).length

		const percentage = (score / Object.keys(moduleResults).length) * 100
		return `- ${moduleName}: ${percentage.toFixed(2)}%`
	})

	fs.writeFileSync(
		'.test-results.md',
		`## Testing complete\n\n${readableResults.join('\n')}\n\n<details><summary>Results</summary>\n\n\`\`\`json\n` +
			JSON.stringify(testResults, null, '\t') +
			'\n```\n\n</details>'
	)
}

start()
