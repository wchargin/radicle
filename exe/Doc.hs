-- | This executable processes literate radicle files. It accepts Markdown, and
-- runs the code inside code blocks (within three backticks).
module Doc where

import           Options.Applicative
import           Protolude
import           Radicle
import           System.Console.Haskeline (defaultSettings, runInputT)
import           Text.Pandoc

main :: IO ()
main = do
    opts' <- execParser allOpts
    run (srcFile opts')
  where
    allOpts = info (opts <**> helper)
       ( fullDesc
      <> progDesc "Radicle literate file tester"
      <> header "radlit"
       )

run :: FilePath -> IO ()
run f = do
    txt <- readFile f
    pand <- runIOorExplode $ readMarkdown def txt
    res <- runInputT defaultSettings $ runLang replBindings $ interpretMany (toS f) $ getCode pand
    case res of
        (Left err, _) -> die . toS $ "Error: " ++ show err
        _             -> pure ()

getCode :: Pandoc -> Text
getCode (Pandoc _ blocks)
    = toS $ mconcat [ content | CodeBlock attr content <- blocks ]

newtype Opts = Opts
    { srcFile :: FilePath
    }

opts :: Parser Opts
opts = Opts <$> argument str (metavar "FILE")
