# privatexcframeworkpackaging plugin

[![fastlane Plugin Badge](https://rawcdn.githack.com/fastlane/fastlane/master/fastlane/assets/plugin-badge.svg)](https://rubygems.org/gems/fastlane-plugin-privatexcframeworkpackaging)

## Getting Started

This project is a [_fastlane_](https://github.com/fastlane/fastlane) plugin. To get started with `fastlane-plugin-privatexcframeworkpackaging`, add it to your project by running:

```bash
fastlane add_plugin privatexcframeworkpackaging
```

## About privatexcframeworkpackaging

Create a Swift package wrapping XCFramework in a private repository.

## Preparation

### GitHub CLI

To use this plugin, you need to use GitHub CLI. Please authenticate your GitHub CLI account beforehand.

[Github CLI](https://cli.github.com/)
[Github CLI - gh auth login](https://cli.github.com/manual/gh_auth_login)

### Preparation of the Swift Package Project to be Introduced

This plugin performs the following tasks:

1. It zips the XCFramework contained in the XCFrameworks directory located directly under the root directory.
2. It automatically creates a release version for binary distribution.
3. It automatically uploads the XCFramework zip file to the release assets of the release version for distribution.
4. It automatically updates the Package.swift file using the uploaded zip file in the release assets.
5. It automatically generates a pull request for the release.

Note that the generation of XCFramework needs to be considered separately using some other method.

### Creation of the XCFrameworks Directory


Create a directory named "XCFrameworks" directly under the project directory. Place the XCFramework that you want to distribute in this directory, which you intend to distribute through a private repository.

```sh
mkdir ./XCFrameworks
```

### Create a configuration file

Create a file named "PrivatePackageConfig.yml" directly under the project directory.

The following is an example entry for "PrivatePackageConfig.yml". Please modify it accordingly to suit your installation environment.

```yml
default_branch_name: "main" # Default branch name for repository
package_name: "PrivateXCFrameworkPackagingExampleFramework" # Package name in Package.swift
libraries: # Library item settings included in the Product array (multiple settings possible)
 - name: "SampleFramework" # Library Name
   targets: # Name of binary target to include in library
    - "SampleFramework" # binary target name
binary_targets: # Binary target name. Use the same name as the XCFramework name.
 - "SampleFramework" # XCFramework name
```

## Example

For sample projects, please refer to the repository below.
[PrivateXCFrameworkPackagingExampleFramework](https://github.com/MasamiYamate/PrivateXCFrameworkPackagingExampleFramework)

## Issues and Feedback

For any other issues and feedback about this plugin, please submit it to this repository.

## Troubleshooting

If you have trouble using plugins, check out the [Plugins Troubleshooting](https://docs.fastlane.tools/plugins/plugins-troubleshooting/) guide.

## Using _fastlane_ Plugins

For more information about how the `fastlane` plugin system works, check out the [Plugins documentation](https://docs.fastlane.tools/plugins/create-plugin/).

## About _fastlane_

_fastlane_ is the easiest way to automate beta deployments and releases for your iOS and Android apps. To learn more, check out [fastlane.tools](https://fastlane.tools).
