require 'fastlane/action'
require 'yaml'

module Fastlane
  module Actions
    class PrivatexcframeworkpackagingAction < Action
      def self.run(params)
        # Configの読み込み
        config = loadConfig
        makeLibraries(config)
        # 事前準備
        prepareBinaryUpload(config)
        # タグを取得する
        latestTagResult = fetchLatestTag
        # binary配布用のVersionを発行する
        assetVersion = makeBinaryReleaseVersion(latestTagResult)
        # リリースアセットにUpするZipを生成する
        makeXCFrameworkZip
        # Checksumを生成
        checksumItems = makeXCFrameworkCheckSum(config)
        # Upload
        uploadBinaryForReleaseAsset(assetVersion)
        assetUrls = fetchReleaseAssetUrls(assetVersion)

        # ここからリリース用のPR作成フロー
        # 作業ブランチの作成
        newVersion = assetVersion.split("_").shift
        branchName = checkoutPackageUpdateBranch(newVersion)
        # Package.swiftの更新
        updatePackage(config, checksumItems, assetUrls)
        # Pull requestの発行
        makeBinaryUpdatePullRequest(config, newVersion, branchName)
      end

      # 事前準備
      def self.prepareBinaryUpload(config)
        # 既に作業用ディレクトリがある場合は削除する
        `rm -rf ./Build/Zip`
        # Baseブランチへの切り替え
        baseBranchName = config["baseBranchName"]
        # 最新の状態を取得する
        `git checkout #{baseBranchName} ; git pull`
        # 最新の状態を取得する
        `git checkout #{baseBranchName} ; git pull`
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

      # binaryリリース用のバージョンを発行する
      def self.makeBinaryReleaseVersion(latestTagResult)
        splitVersionItems = latestTagResult.split(".")
        # マイナーバージョンUp
        minorVersion = splitVersionItems[1].to_i + 1
        newVersion = splitVersionItems[0] + "." + minorVersion.to_s + "." + splitVersionItems[2].sub(/_.*/m, "")
        # リリースアセット用のVersionの発行
        nowTime = Time.now
        assetVersion = newVersion + "_binary_" + format("%04<number>d", number: nowTime.year) + format("%02<number>d", number: nowTime.month) + format("%02<number>d", number: nowTime.day) + "_" + format("%02<number>d", number: nowTime.hour) + format("%02<number>d", number: nowTime.min) + format("%02<number>d", number: nowTime.sec)
        `bundle exec gh release create #{assetVersion}`
        return assetVersion
      end

      # 各frameworkをZipに圧縮する
      def self.makeXCFrameworkZip
        xcframeworksPath = "./XCFrameworks"
        workDirPath = "./Build/Zip"
        # 作業用ディレクトリの作成
        `mkdir -p #{workDirPath}`
        Dir.foreach(xcframeworksPath) do |item|
          next if item == '.' or item == '..' or item == '.DS_Store'
          zipFilePath = workDirPath + '/' + item + '.zip'
          xcframeworkPath = xcframeworksPath + '/' + item
          `zip -r -X #{zipFilePath} #{xcframeworkPath}`
        end
      end

      # 各XCFramework zipのchecksumを取得する
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

      # Package更新用のブランチをチェックアウト
      def self.checkoutPackageUpdateBranch(newVersion)
        # Version発行後の最新の状態を取得する
        `git pull`
        # 作業用ブランチの作成
        branchName = "feature/update-#{newVersion}"
        currentBranch = `git branch --contains | cut -d " " -f 2`
        if branchName != currentBranch then
          gitDiffExitCode = `git fetch #{branchName} & echo $?`.chomp
          `git checkout -b #{branchName}`
        end
        return branchName
      end

      # Update用のPull Requestを発行する
      def self.makeBinaryUpdatePullRequest(config, newVersion, branchName)
        `git add .`
        `git commit -m "Update binary #{newVersion}"`
        `git push --set-upstream origin #{branchName}`

        baseBranchName = config["baseBranchName"]
        title = "Update #{newVersion}"
        body = "Update XCFrameworks Version #{newVersion}"
        `bundle exec gh pr create --base "#{baseBranchName}" --head "#{branchName}" --title "#{title}" --body "#{body}"`
      end

      # binary targetの各項目を生成する
      def self.makeBinaryTargets(config, checksumItems, assetUrls)
        result = []
        binaryTargetTemplate = fetchTemplate("packageBinaryTargetTemplate.txt")
        binaryTargets = config["binaryTargets"]
        for binaryTargetName in binaryTargets
          checksum = checksumItems[binaryTargetName]
          assetUrl = assetUrls[binaryTargetName] + ".zip"
          binaryTargetItem = binaryTargetTemplate.gsub("${binary_target_name}", binaryTargetName).gsub("${binary_target_url}", assetUrl).gsub("${binary_check_sum}", checksum)
          result.push(binaryTargetItem)
        end
        return result
      end

      # libraryの各項目を生成する
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

      # Package.swiftを更新する
      def self.updatePackage(config, checksumItems, assetUrls)
        binaryTargets = makeBinaryTargets(config, checksumItems, assetUrls).join(",")
        libraries = makeLibraries(config).join(",")
        packageName = config["packageName"]
        updatePackageTemplate = fetchTemplate("packageBaseTemplate.txt")
        updatePackageTxt = updatePackageTemplate.gsub("${package_name}", packageName).gsub("${product_items}", libraries).gsub("${binary_targets}", binaryTargets)
        open("./Package.swift", 'w') do |file|
          file.puts(updatePackageTxt)
        end
      end

      # binaryをUploadする
      def self.uploadBinaryForReleaseAsset(tag)
        zipDir = "./Build/Zip"
        Dir.foreach(zipDir) do |item|
          next if item == '.' or item == '..' or item == '.DS_Store'
          frameworkPath = zipDir + "/" + item
          `bundle exec gh release upload #{tag} #{frameworkPath}`
        end
      end

      # 設定ファイルを取得する
      def self.loadConfig
        return open('PrivatePackageConfig.yml', 'r') { |file| YAML.load(file) }
      end

      # Upload済みのRelease Assetsのapi urlを取得する
      def self.fetchReleaseAssetUrls(tag)
        result = {}
        assetsJson = `bundle exec gh release view #{tag} --json assets`
        assetsHash = JSON.load(assetsJson)
        assets = assetsHash["assets"]
        for asset in assets
          apiUrl = asset["apiUrl"]
          frameworkName = extractionFrameworkname(asset["name"])
          result[frameworkName] = apiUrl
        end
        return result
      end

      # Package.swift更新用の各テンプレートファイルを抽出する
      def self.fetchTemplate(fileName)
        directoryPathItems = __dir__.split(File::SEPARATOR)
        directoryPathItems.pop
        pluginRootDirPath = directoryPathItems.join(File::Separator)
        templateFile = open(pluginRootDirPath + '/template/' + fileName, 'r')
        return templateFile.read
      end

      # 拡張子付きのファイル名からFramework名称を抽出する
      def self.extractionFrameworkname(fileName)
        # hogeFuga.xcframeworkやhogeFuga.xcframework.zipからファイル名を抽出する
        return fileName.split(".").shift
      end

      # 最新のタグを取得する
      def self.fetchLatestTag
        # タグを取得する
        latestTagResult = `git describe --tags`.chomp
        if latestTagResult == ""
          latestTagResult = "0.0.0"
        end
        return latestTagResult
      end

      def self.description
        "Generate a Swift package using the XCFramework uploaded to the Release assets of a private repository."
      end

      def self.authors
        ["Masami Yamate"]
      end

      def self.return_value
      end

      def self.details
        "Generate a Swift package using the XCFramework uploaded to the Release assets of a private repository."
      end

      def self.available_options
        []
      end

      def self.is_supported?(platform)
        [:ios, :mac].include?(platform)
      end
    end
  end
end
