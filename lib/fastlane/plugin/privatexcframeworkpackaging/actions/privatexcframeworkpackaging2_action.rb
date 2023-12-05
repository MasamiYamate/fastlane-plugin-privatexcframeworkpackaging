require 'fastlane/action'
require 'yaml'
require_relative '../helper/privatexcframeworkpackaging_helper'

module Fastlane
  module Actions
    class Privatexcframeworkpackaging2Action < Action
      def self.run(params)
        # Configの読み込み
        config = loadConfig
        makeLibraries(config)
        # # 事前準備
        # prepareBinaryUpload(config)
        # # タグを取得する
        # latestTagResult = fetchLatestTag
        # # binary配布用のVersionを発行する
        # assetVersion = makeBinaryReleaseVersion(latestTagResult)
        # # リリースアセットにUpするZipを生成する
        # makeXCFrameworkZip
        # # Checksumを生成
        # checksumItems = makeXCFrameworkCheckSum(config)
        # # Upload
        # uploadBinaryForReleaseAsset(assetVersion)
        # assetUrls = fetchReleaseAssetUrls(assetVersion)

        # # ここからリリース用のPR作成フロー
        # # 作業ブランチの作成
        # makePackageUpdateBranch(assetVersion)
        # updatePackage(config, checksumItems, assetUrls)
        # # ZIP作業用フォルダの作成
        # `mkdir ./XCFrameworks/zip`
        # # # binary targetの名称を抽出
        # fetchTemplate("packageBinaryTargetTemplate.txt")
        # binaryTargetTemplate = open(pluginRootDirPath + '/template/packageBinaryTargetTemplate.txt', 'r')
        # p binaryTargetTemplate
        # binaryTargets = config["binaryTargets"]
        # for binaryTarget in binaryTargets
        #   p binaryTarget
        # end
      end

      def self.prepareBinaryUpload(config)
        # 既に作業用ディレクトリがある場合は削除する
        `rm -rf ./Build/Zip`
        # # defaultブランチへの切り替え
        defaultBranchName = config["defaultBranchName"]
        # 最新の状態を取得する
        `git checkout #{defaultBranchName} ; git pull`
        # 最新の状態を取得する
        `git checkout #{defaultBranchName} ; git pull`
        # XCFrameworkのディレクトリの確認
        if !Dir.exist?("./XCFrameworks") then
          throw Exception.new("There is no directory to save XCFramework")
        end
        # git diffがないことを確認する
        gitDiffExitCode = `git diff --exit-code --quiet & echo $?`.chomp
        if gitDiffExitCode != "0" then
          throw Exception.new("There are differences")
        end
      end

      def self.makeBinaryReleaseVersion(latestTagResult)
        splitVersionItems = latestTagResult.split(".")
        # マイナーバージョンUp
        minorVersion = splitVersionItems[1].to_i + 1
        newVersion = splitVersionItems[0] + "." + minorVersion.to_s + "." + splitVersionItems[2].sub(/_.*/m, "")
        # リリースアセット用のVersionの発行
        nowTime = Time.now
        assetVersion = newVersion + "_binary_" + format("%04<number>d", number: nowTime.year) + format("%02<number>d", number: nowTime.month) + format("%02<number>d", number: nowTime.day) + "_" + format("%02<number>d", number: nowTime.hour) + format("%02<number>d", number: nowTime.min) + format("%02<number>d", number: nowTime.sec)
        `gh release create #{assetVersion}`
        return assetVersion
      end

      def self.makeXCFrameworkZip
        xcframeworksPath = "./XCFrameworks"
        workDirPath = "./Build/Zip"
        # 作業用ディレクトリの作成
        Dir.mkdir(workDirPath)
        Dir.foreach(xcframeworksPath) do |item|
          next if item == '.' or item == '..' or item == '.DS_Store'
          zipFilePath = workDirPath + '/' + item + '.zip'
          xcframeworkPath = xcframeworksPath + '/' + item
          `zip -r -X #{zipFilePath} #{xcframeworkPath}`
        end
      end

      def self.makeXCFrameworkCheckSum(config)
        result = {}
        zipDir = "./Build/Zip"
        Dir.foreach(zipDir) do |item|
          next if item == '.' or item == '..' or item == '.DS_Store'
          frameworkPath = zipDir + "/" + item
          checksum = `shasum -a 256 #{frameworkPath}`.split( ).shift
          frameworkName = extractionFrameworkname(item)
          result[frameworkName] = checksum
        end
        return result
      end

      def self.makePackageUpdateBranch(assetVersion)
        # Version発行後の最新の状態を取得する
        `git pull`
        # 作業用ブランチの作成
        newVersion = assetVersion.split("_").shift
        `git checkout -b feature/update-#{newVersion}`
      end

      def self.makeBinaryTargets(config, checksumItems, assetUrls)
        result = []
        binaryTargetTemplate = fetchTemplate("packageBinaryTargetTemplate.txt")
        binaryTargets = config["binaryTargets"]
        for binaryTargetName in binaryTargets
          checksum = checksumItems[binaryTargetName]
          assetUrl = assetUrls[binaryTargetName]
          binaryTargetItem = binaryTargetTemplate.gsub("${binary_target_name}", binaryTargetName).gsub("${binary_target_url}", assetUrl).gsub("${binary_check_sum}", checksum)
          result.push(binaryTargetItem)
        end
        return result
      end

      def self.makeLibraries(config)
        result = []
        libraryTemplate = fetchTemplate("packageLibraryItemTemplate.txt")
        libraries = config["libraries"]
        for library in libraries
          name = library["name"]
          targets = library["targets"].map { |target| "\"" + target + "\"" }.join(",")
          libraryItem = libraryTemplate.gsub("${library_name}", name).gsub("${library_targets}", targets)
          result.push(libraryItem)
        end
        return result
      end

      def self.updatePackage(config, checksumItems, assetUrls)
        binaryTargets = makeBinaryTargets(config, checksumItems, assetUrls).join(",")
        libraries = makeLibraries(config).join(",")
        p binaryTargets
      end


      def self.uploadBinaryForReleaseAsset(tag)
        zipDir = "./Build/Zip"
        Dir.foreach(zipDir) do |item|
          next if item == '.' or item == '..' or item == '.DS_Store'
          frameworkPath = zipDir + "/" + item
          `gh release upload #{tag} #{frameworkPath}`
        end
      end

      def self.loadConfig
        return open('PrivatePackageConfig.yml', 'r') { |f| YAML.load(f) }
      end

      def self.fetchReleaseAssetUrls(tag)
        result = {}
        assetsJson = `gh release view #{tag} --json assets`
        assetsHash = JSON.load(assetsJson)
        assets = assetsHash["assets"]
        for asset in assets
          apiUrl = asset["apiUrl"]
          frameworkName = extractionFrameworkname(asset["name"])
          result[frameworkName] = apiUrl
        end
        return result
      end

      def self.fetchTemplate(fileName)
        directoryPathItems = __dir__.split(File::SEPARATOR)
        directoryPathItems.pop
        pluginRootDirPath = directoryPathItems.join(File::Separator)
        templateFile = open(pluginRootDirPath + '/template/' + fileName, 'r')
        return templateFile.read
      end

      def self.extractionFrameworkname(fileName)
        # hogeFuga.xcframeworkやhogeFuga.xcframework.zipからファイル名を抽出する
        return fileName.split(".").shift
      end

      def self.fetchLatestTag
        # タグを取得する
        latestTagResult = `git describe --tags`.chomp
        if latestTagResult == ""
          latestTagResult = "0.0.0"
        end
        return latestTagResult
      end

      def self.description
        "hoge"
      end

      def self.authors
        ["Masami Yamate"]
      end

      def self.return_value
        # If your method provides a return value, you can describe here what it does
      end

      def self.details
        # Optional:
        "hoge"
      end

      def self.available_options
        [
          # FastlaneCore::ConfigItem.new(key: :your_option,
          #                         env_name: "PRIVATEXCFRAMEWORKPACKAGING_YOUR_OPTION",
          #                      description: "A description of your option",
          #                         optional: false,
          #                             type: String)
        ]
      end

      def self.is_supported?(platform)
        # Adjust this if your plugin only works for a particular platform (iOS vs. Android, for example)
        # See: https://docs.fastlane.tools/advanced/#control-configuration-by-lane-and-by-platform
        #
        # [:ios, :mac, :android].include?(platform)
        true
      end
    end
  end
end
