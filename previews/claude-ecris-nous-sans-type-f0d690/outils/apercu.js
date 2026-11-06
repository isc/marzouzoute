// L'image des balises og: de index.html (voir CLAUDE.md) : og-image.jpg, 1200 × 630.
// Elle montre le vrai accueil, son titre et quelques vignettes de chaque famille,
// dans un navigateur pour avoir leurs polices et leurs dessins.
//     NODE_PATH=$(npm root -g) node outils/apercu.js

const path = require("path")
const { chromium } = require("playwright")

const RACINE = path.join(__dirname, "..")

const JEUX = [
  "b-ou-d",
  "sutom",
  "2048",
  "memory",
  "othello",
  "tabou",
  "ou-ou-on",
  "lettris",
  "fracto-dingo",
  "demineur",
  "qwirkle",
  "anagramme",
]

const STYLE = `
  .hero-bar, #search-bar { display: none; }
  body { height: 630px; }
  .container { max-width: none; padding: 0 40px; }
  .hero { padding: 40px 40px 0; text-align: center; }
  .wordmark { font-size: 104px; margin: 0; }
  .tagline { font-size: 32px; margin: 4px 0 0; max-width: none; }
  .game-grid { grid-template-columns: repeat(6, 1fr); margin-top: 32px; }
`

async function main() {
  const navigateur = await chromium.launch()
  const page = await navigateur.newPage({
    viewport: { width: 1200, height: 630 },
    reducedMotion: "reduce",
  })
  await page.goto(`file://${path.join(RACINE, "index.html")}`)
  await page.addStyleTag({ content: STYLE })
  await page.evaluate((jeux) => {
    const vignettes = jeux.map((jeu) =>
      document.querySelector(`.game[data-game="${jeu}"]`),
    )
    if (vignettes.includes(null)) throw new Error("Un jeu de JEUX n'existe plus")
    const grille = document.querySelector(".game-grid")
    grille.replaceChildren(...vignettes)
    document.getElementById("catalogue").replaceChildren(grille)
  }, JEUX)
  await page.screenshot({
    path: path.join(RACINE, "og-image.jpg"),
    quality: 88,
  })
  await navigateur.close()
}

main()
