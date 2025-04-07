const webpack = require("webpack");
const path = require("path");
const MiniCssExtractPlugin = require("mini-css-extract-plugin");
const CssMinimizerPlugin = require("css-minimizer-webpack-plugin");
const { ESBuildMinifyPlugin } = require("esbuild-loader");

module.exports = ({ appName, indexPath }) => {
    const isInDevMode = process.env.TARGET_ENV === "development";
    const assetsHost = isInDevMode ? "http://localhost:3900/" : "";
    const isInWatchMode =
        process.env.WATCH_MODE === "true"
            ? true
            : process.env.WATCH_MODE === "false"
              ? false
              : isInDevMode;
    const shouldRunDebugMode = process.env.DEBUG_MODE === "true";
    const entry = {};
    entry[appName] = indexPath;

    if (isInDevMode) {
        console.info("Running in development mode for", appName);
    }

    const moduleRules = [
        {
            test: /\.html$/,
            exclude: /node_modules/,
            loader: "file-loader",
            options: {
                name: "[name].[ext]"
            }
        },
        {
            test: /\.elm$/,
            exclude: [/elm-stuff/, /node_modules/],
            use: [
                // fix for Safari 15.1 bug
                {
                    loader: "string-replace-loader",
                    options: {
                        search: /^(\s*)for \(var (\w+) in (\w+)\)\s*\{/gm,
                        replace: `$1for (var __keys_$2 = Object.keys($3), __i_$2 = 0; __i_$2 < __keys_$2.length; __i_$2++) { var $2 = __keys_$2[__i_$2];`
                    }
                },
                {
                    loader: "elm-webpack-loader",
                    options: {
                        optimize: !isInDevMode,
                        pathToElm: "node_modules/.bin/elm",
                        debug: shouldRunDebugMode
                    }
                }
            ]
        },
        {
            test: /\.(sa|sc|c)ss$/,
            use: [
                MiniCssExtractPlugin.loader,
                {
                    loader: "css-loader",
                    options: {
                        sourceMap: true
                    }
                },
                "postcss-loader",
                {
                    loader: "sass-loader",
                    options: {
                        sourceMap: true,
                        sassOptions: {
                            includePaths: ["client"],
                            // Silencing deprecation warnings for now, but we should migrate to Dart Sass 2.0.0 soon
                            quietDeps: true,
                            silenceDeprecations: ["legacy-js-api"]
                            // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
                        }
                    }
                }
            ]
        },
        {
            test: /\.(woff|woff2|otf|eot|ttf)$/,
            use: [
                {
                    loader: "url-loader",
                    options: {
                        limit: 10000,
                        name: "[folder]/[hash].[ext]",
                        outputPath: assetsHost + "assets"
                    }
                }
            ]
        },
        {
            test: /\.(jpe?g|png|gif|svg)$/,
            use: [
                {
                    loader: "url-loader",
                    options: {
                        limit: 10000,
                        name: "[folder]/[hash].[ext]",
                        outputPath: assetsHost + "assets"
                    }
                },
                {
                    loader: "image-webpack-loader",
                    options: {
                        disable: false // webpack@2.x and newer
                    }
                }
            ]
        },
        {
            test: /\.js$/,
            exclude: /(node_modules|elm-stuff)/,
            loader: "babel-loader",
            options: {
                babelrc: true
            }
        },
        {
            test: /\.ts$/,
            use: "ts-loader",
            exclude: /elm-stuff/
        }
    ];

    if (isInDevMode) {
        moduleRules.unshift({
            test: /\.(j|t)s$/,
            exclude: [/elm-stuff/, /node_modules/],
            use: [
                {
                    loader: "string-replace-loader",
                    options: {
                        search: new RegExp(`"\/(assets\/${appName}\.css)`, "gm"),
                        replace: `"${assetsHost}$1`
                    }
                }
            ]
        });
    }

    const cacheGroups = {
        default: false,
        styles: {
            name: "styles",
            test: /\.css$/,
            chunks: "all",
            enforce: true
        }
    };
    cacheGroups[appName] = {
        name: appName,
        test: /\.js$/,
        chunks: "all",
        enforce: true
    };

    return {
        bail: !isInWatchMode,
        entry: entry,
        watch: isInWatchMode,
        output: {
            path: path.join(__dirname, "../build"),
            filename: "[name].js",
            library: appName,
            libraryTarget: "amd",
            pathinfo: true,
            publicPath: "/"
        },
        mode: "production",
        devtool: "source-map",

        resolve: {
            alias: {
                // css-loader handles only relative paths in url() now, so this alias
                // enables us to use "absolute" paths (with `client/` as a root)
                "/assets": path.resolve(__dirname, "./assets/")
            },
            enforceExtension: false,
            extensions: [".ts", ".js", ".elm", ".scss"],
            modules: [path.join(__dirname, "."), "node_modules"]
        },

        optimization: {
            splitChunks: {
                cacheGroups: cacheGroups
            },
            minimize: true,
            minimizer: [
                new ESBuildMinifyPlugin({
                    include: appName,
                    target: "es2015"
                }),
                new CssMinimizerPlugin()
            ]
        },
        module: {
            rules: moduleRules,
            noParse: /\.elm$/
        },
        plugins: [
            new MiniCssExtractPlugin({
                filename: `assets/${appName}.css`
            }),
            new webpack.DefinePlugin({
                "process.env": {
                    TARGET_ENV: JSON.stringify(process.env.TARGET_ENV) || '"development"' // determines Env in Flags
                }
            })
        ],
        devServer: {
            hot: true,
            historyApiFallback: {
                disableDotRule: true
            },
            compress: true,
            static: {
                watch: {
                    aggregateTimeout: 1000
                }
            },
            allowedHosts: "all"
        }
    };
};
