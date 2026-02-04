const webpack = require("webpack");
const path = require("path");
const HtmlWebpackPlugin = require("html-webpack-plugin");
const MiniCssExtractPlugin = require("mini-css-extract-plugin");

const baseConfig = require("../../webpack.default.config.ts");

module.exports = (env, options) => {
    // Get the base config
    const config = baseConfig({
        appName: "crosstabs",
        indexPath: path.join(__dirname, "./standalone.ts")
    });

    // Override for standalone mode
    config.output.libraryTarget = "umd";
    config.mode = "development";
    config.optimization.minimize = false;

    // Remove sentryWebpackPlugin from plugins
    config.plugins = config.plugins.filter(
        (plugin) => plugin.constructor.name !== "SentryWebpackPlugin"
    );

    // Add HtmlWebpackPlugin for standalone HTML shell
    config.plugins.push(
        new HtmlWebpackPlugin({
            template: path.join(__dirname, "./standalone.html"),
            filename: "index.html",
            inject: "body"
        })
    );

    // Override DefinePlugin to ensure TARGET_ENV is development
    config.plugins = config.plugins.map((plugin) => {
        if (plugin instanceof webpack.DefinePlugin) {
            return new webpack.DefinePlugin({
                "process.env": {
                    TARGET_ENV: JSON.stringify("development")
                }
            });
        }
        return plugin;
    });

    // Dev server config
    config.devServer = {
        hot: true,
        port: 3005,
        host: "0.0.0.0",
        historyApiFallback: {
            disableDotRule: true
        },
        compress: true,
        static: {
            watch: {
                aggregateTimeout: 1000
            }
        },
        allowedHosts: "all",
        proxy: [
            {
                context: ["/api", "/v1", "/v2", "/platform"],
                target: "http://localhost:4000",
                changeOrigin: true
            }
        ]
    };

    // Remove watch property — webpack-dev-server manages this itself
    delete config.watch;
    config.bail = false;

    // Exclude standalone.html from file-loader so HtmlWebpackPlugin can use it as a template
    config.module.rules = config.module.rules.map((rule) => {
        if (rule.test && rule.test.toString() === "/\\.html$/") {
            return { ...rule, exclude: [/node_modules/, /standalone\.html$/] };
        }
        return rule;
    });

    // Set ts-loader to transpileOnly for faster builds and to skip pre-existing type errors
    config.module.rules.forEach((rule) => {
        if (rule.use === "ts-loader") {
            rule.use = { loader: "ts-loader", options: { transpileOnly: true } };
        }
    });

    return config;
};
