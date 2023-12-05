describe Fastlane::Actions::PrivatexcframeworkpackagingAction do
  describe '#run' do
    it 'prints a message' do
      expect(Fastlane::UI).to receive(:message).with("The privatexcframeworkpackaging plugin is working!")

      Fastlane::Actions::PrivatexcframeworkpackagingAction.run(nil)
    end
  end
end
