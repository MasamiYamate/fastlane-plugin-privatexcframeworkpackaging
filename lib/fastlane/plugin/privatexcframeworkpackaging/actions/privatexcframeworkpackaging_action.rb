require 'fastlane/action'
require 'yaml'

module Fastlane
  module Actions
    class PrivatexcframeworkpackagingAction < Action
      def self.run(params)
        # Configの読み込み
        config = load_config
        make_libraries(config)
        # 事前準備
        prepare_binary_upload(config)
        # タグを取得する
        latest_tag_result = fetch_latest_tag
        # binary配布用のVersionを発行する
        asset_version = make_binary_release_version(latest_tag_result)
        # リリースアセットにUpするZipを生成する
        make_xcframework_xip
        # Checksumを生成
        checksum_items = make_xcframework_checksum(config)
        # Upload
        upload_binary_for_release_asset(asset_version)
        asset_urls = fetch_release_asset_urls(asset_version)

        # ここからリリース用のPR作成フロー
        # 作業ブランチの作成
        new_version = asset_version.split('_').shift
        branch_name = checkout_package_update_branch(new_version)
        # Package.swiftの更新
        update_package(config, checksum_items, asset_urls)
        # Pull requestの発行
        make_binary_update_pull_request(config, new_version, branch_name)
      end

      # 事前準備
      def self.prepare_binary_upload(config)
        # 既に作業用ディレクトリがある場合は削除する
        `rm -rf ./Build/Zip`
        # Baseブランチへの切り替え
        basebranch_name = config['defaultbranch_name']
        # 最新の状態を取得する
        `git checkout #{basebranch_name} ; git pull`
        # 最新の状態を取得する
        `git checkout #{basebranch_name} ; git pull`
        # XCFrameworkのディレクトリの確認
        unless Dir.exist?('./XCFrameworks')
          throw Exception.new('There is no directory to save XCFramework')
        end
        # git diffがないことを確認する
        git_diff_exit_code = `git diff --exit-code --quiet & echo $?`.chomp
        if git_diff_exit_code != '0'
          throw Exception.new('There are differences')
        end
      end

      # binaryリリース用のバージョンを発行する
      def self.make_binary_release_version(latest_tag_result)
        split_version_items = latest_tag_result.split('.')
        # マイナーバージョンUp
        minor_version = split_version_items[1].to_i + 1
        new_version = "#{split_version_items[0]}.#{minor_version}.#{split_version_items[2].sub(/_.*/m, '')}"
        # リリースアセット用のVersionの発行
        now_time = Time.now
        ymd_string = "#{format('%04<number>d', number: now_time.year)}#{format('%02<number>d', number: now_time.month)}#{format('%02<number>d', number: now_time.day)}"
        hms_string = "#{format('%02<number>d', number: now_time.hour)}#{format('%02<number>d', number: now_time.min)}#{format('%02<number>d', number: now_time.sec)}"
        asset_version = "#{new_version}_binary_#{ymd_string}_#{hms_string}"
        `bundle exec gh release create #{asset_version}`
        return asset_version
      end

      # 各frameworkをZipに圧縮する
      def self.make_xcframework_xip
        xcframeworks_path = './XCFrameworks'
        work_dir_path = './Build/Zip'
        # 作業用ディレクトリの作成
        `mkdir -p #{work_dir_path}`
        Dir.foreach(xcframeworks_path) do |item|
          next if item == '.' || item == '..' || item == '.DS_Store'

          zip_file_path = "#{work_dir_path}/#{item}.zip"
          xcframework_path = "#{xcframeworks_path}/#{item}"
          `zip -r -X #{zip_file_path} #{xcframework_path}`
        end
      end

      # 各XCFramework zipのchecksumを取得する
      def self.make_xcframework_checksum(config)
        result = {}
        zip_dir = './Build/Zip'
        Dir.foreach(zip_dir) do |item|
          next if item == '.' || item == '..' || item == '.DS_Store'

          framework_path = "#{zip_dir}/#{item}"
          checksum = `shasum -a 256 #{framework_path}`.split( ).shift
          framework_name = extraction_framework_name(item)
          result[framework_name] = checksum
        end
        return result
      end

      # Package更新用のブランチをチェックアウト
      def self.checkout_package_update_branch(new_version)
        # Version発行後の最新の状態を取得する
        `git pull`
        # 作業用ブランチの作成
        branch_name = "feature/update-#{new_version}"
        current_branch = `git branch --contains | cut -d ' ' -f 2`
        if branch_name != current_branch
          `git checkout -b #{branch_name}`
        end
        return branch_name
      end

      # Update用のPull Requestを発行する
      def self.make_binary_update_pull_request(config, new_version, branch_name)
        `git add .`
        commit_message = "Update binary #{new_version}"
        `git commit -m "#{commit_message}"`
        `git push --set-upstream origin #{branch_name}`

        basebranch_name = config['basebranch_name']
        title = "Update #{new_version}"
        body = "Update XCFrameworks Version #{new_version}"
        `bundle exec gh pr create --base "#{basebranch_name}" --head "#{branch_name}" --title "#{title}" --body "#{body}"`
      end

      # binary targetの各項目を生成する
      def self.make_binary_targets(config, checksum_items, asset_urls)
        result = []
        binary_target_template = fetch_template('package_binary_target_template.txt')
        binary_targets = config['binary_targets']
        for binary_target_name in binary_targets
          checksum = checksum_items[binary_target_name]
          asset_url = "#{asset_urls[binary_target_name]}.zip"
          binary_target_item = binary_target_template.gsub('${binary_target_name}', binary_target_name).gsub('${binary_target_url}', asset_url).gsub('${binary_check_sum}', checksum)
          result.push(binary_target_item)
        end
        return result
      end

      # libraryの各項目を生成する
      def self.make_libraries(config)
        result = []
        library_template = fetch_template('package_library_item_template.txt')
        libraries = config['libraries']
        for library in libraries
          name = library['name']
          targets = library['targets'].map { |target| '\'' + target + '\'' }.join(',')
          library_item = library_template.gsub('${library_name}', name).gsub('${library_targets}', targets)
          result.push(library_item)
        end
        return result
      end

      # Package.swiftを更新する
      def self.update_package(config, checksum_items, asset_urls)
        binary_targets = make_binary_targets(config, checksum_items, asset_urls).join(',')
        libraries = make_libraries(config).join(',')
        package_name = config['package_name']
        update_package_template = fetch_template('package_base_template.txt')
        update_package_txt = update_package_template.gsub('${package_name}', package_name).gsub('${product_items}', libraries).gsub('${binary_targets}', binary_targets)
        open('./Package.swift', 'w') do |file|
          file.puts(update_package_txt)
        end
      end

      # binaryをUploadする
      def self.upload_binary_for_release_asset(tag)
        zip_dir = './Build/Zip'
        Dir.foreach(zip_dir) do |item|
          next if item == '.' || item == '..' || item == '.DS_Store'
          
          framework_path = "#{zip_dir}/#{item}"
          `bundle exec gh release upload #{tag} #{framework_path}`
        end
      end

      # 設定ファイルを取得する
      def self.load_config
        return open('PrivatePackageConfig.yml', 'r') { |file| YAML.load(file) }
      end

      # Upload済みのRelease Assetsのapi urlを取得する
      def self.fetch_release_asset_urls(tag)
        result = {}
        assets_json = `bundle exec gh release view #{tag} --json assets`
        assets_hash = JSON.load(assets_json)
        assets = assets_hash['assets']
        for asset in assets
          api_url = asset['apiUrl']
          framework_name = extraction_framework_name(asset['name'])
          result[framework_name] = api_url
        end
        return result
      end

      # Package.swift更新用の各テンプレートファイルを抽出する
      def self.fetch_template(file_name)
        directory_path_items = __dir__.split(File::SEPARATOR)
        directory_path_items.pop
        plugin_root_dir_path = directory_path_items.join(File::Separator)
        template_file = open("#{plugin_root_dir_path}/template/#{file_name}", 'r')
        return template_file.read
      end

      # 拡張子付きのファイル名からFramework名称を抽出する
      def self.extraction_framework_name(file_name)
        # hogeFuga.xcframeworkやhogeFuga.xcframework.zipからファイル名を抽出する
        return file_name.split('.').shift
      end

      # 最新のタグを取得する
      def self.fetch_latest_tag
        # タグを取得する
        latest_tag_result = `git describe --tags --abbrev=0`.chomp
        if latest_tag_result == ''
          latest_tag_result = '0.0.0'
        end
        return latest_tag_result
      end

      def self.description
        'Generate a Swift package using the XCFramework uploaded to the Release assets of a private repository.'
      end

      def self.authors
        ['Masami Yamate']
      end

      def self.return_value
      end

      def self.details
        'Generate a Swift package using the XCFramework uploaded to the Release assets of a private repository.'
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
