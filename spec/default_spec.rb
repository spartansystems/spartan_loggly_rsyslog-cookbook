require 'spec_helper'

describe 'spartan_loggly_rsyslog::default' do

  before do
    Chef::EncryptedDataBagItem.stub(:load).with('loggly', 'token').and_return(
      { 'id' => 'token', 'token' => 'abc123' })
  end

  let(:chef_run) do
    ChefSpec::Runner.new(CHEF_RUN_OPTIONS).converge(described_recipe)
  end

  context 'when the loggly token is not set' do
    before do
      Chef::EncryptedDataBagItem.stub(:load).with('loggly', 'token').and_return(nil)
    end

    let(:chef_run) { ChefSpec::Runner.new.converge(described_recipe) }

    it 'raises an error' do
      expect {
        chef_run
      }.to raise_error
    end
  end

  context 'with an alternative databag and item name' do
    before do
      Chef::EncryptedDataBagItem.stub(:load).with('credentials', 'loggly_token').and_return(
      { 'id' => 'token', 'token' => 'abc12345' })
    end

    let(:chef_run) do
      ChefSpec::Runner.new(CHEF_RUN_OPTIONS) do |node|
        node.set['loggly']['token']['databag'] = 'credentials'
        node.set['loggly']['token']['databag_item'] = 'loggly_token'
      end.converge(described_recipe)
    end

    it 'sets the correct token in config file' do
      expect(chef_run).to render_file('/etc/rsyslog.d/10-loggly.conf').with_content(/^.*\[abc12345@41058 \] %msg%/)
    end
  end

  context 'when the loggly token is set via an attribute' do
    before do
      Chef::EncryptedDataBagItem.stub(:load).with('loggly', 'token').and_return(nil)
    end

    let(:chef_run) do
      ChefSpec::Runner.new(CHEF_RUN_OPTIONS) do |node|
        node.set['loggly']['token']['from_databag'] = false
        node.set['loggly']['token']['value'] = 'logglytoken1234'
      end.converge(described_recipe)
    end

    it 'sets the correct token in config file' do
      expect(chef_run).to render_file('/etc/rsyslog.d/10-loggly.conf').with_content(/^.*\[logglytoken1234@41058 \] %msg%/)
    end
  end

  context 'when rsyslog tls is disabled' do
    let(:chef_run) do
      ChefSpec::Runner.new(CHEF_RUN_OPTIONS) do |node|
        node.set['loggly']['tls']['enabled'] = false
      end.converge(described_recipe)
    end

    it 'does not include the tls recipe' do
      expect(chef_run).to_not include_recipe "loggly::tls"
    end

    it 'uses 514 as the port' do
      expect(chef_run.node['loggly']['rsyslog']['port']).to eq 514
    end

  end

  it 'contains the correct TLS configuration settings' do
    expect(chef_run).to render_file('/etc/rsyslog.d/10-loggly.conf').with_content(/^\$DefaultNetstreamDriverCAFile \/etc\/rsyslog.d\/keys\/ca.d\/loggly_full.crt/)
    expect(chef_run).to render_file('/etc/rsyslog.d/10-loggly.conf').with_content(/^\$ActionSendStreamDriver gtls/)
    expect(chef_run).to render_file('/etc/rsyslog.d/10-loggly.conf').with_content(/^\$ActionSendStreamDriverMode 1/)
    expect(chef_run).to render_file('/etc/rsyslog.d/10-loggly.conf').with_content(/^\$ActionSendStreamDriverAuthMode x509\/name/)
    expect(chef_run).to render_file('/etc/rsyslog.d/10-loggly.conf').with_content(/^\$ActionSendStreamDriverPermittedPeer \*\.loggly.com/)
  end

  it 'notifies the rsyslog service to restart' do
    rsyslog_template = chef_run.find_resource(:template, '/etc/rsyslog.d/10-loggly.conf')
    expect(rsyslog_template).to notify('service[rsyslog]').to(:restart)
  end

  it 'creates loggly rsyslog template with no tags' do
    expect(chef_run).to create_template('/etc/rsyslog.d/10-loggly.conf').with(
      owner: 'root',
      group: 'root',
      variables: ({
        :tags => '',
        :monitor_files => false,
        :token => 'abc123'
      })
    )
  end

  it 'creates loggly rsyslog template with tags' do
    chef_run.node.set['loggly']['tags'] = ['test', 'foo', 'bar']
    chef_run.converge(described_recipe)
    expect(chef_run).to create_template('/etc/rsyslog.d/10-loggly.conf').with(
      owner: 'root',
      group: 'root',
      variables: ({
        :tags => 'tag=\"test\" tag=\"foo\" tag=\"bar\"',
        :monitor_files => false,
        :token => 'abc123'
      })
    )
  end

  it 'loads the imfile module when log_files is not empty' do
    runner = ChefSpec::Runner.new(CHEF_RUN_OPTIONS) do |node|
      node.set['loggly']['log_files'] =
      [ { filename: '/var/log/somefile', tag: 'sometag', statefile: 'somefile.state' },
        { filename: '/var/log/anotherfile', tag: 'anothertag', statefile: 'anotherfile.state' }
      ]
    end.converge(described_recipe)

    expect(runner).to create_template('/etc/rsyslog.d/10-loggly.conf').with(
      owner: 'root',
      group: 'root',
      variables: ({
        :tags => '',
        :monitor_files => true,
        :token => 'abc123'
      })
    )

    expect(runner).to render_file('/etc/rsyslog.d/10-loggly.conf').with_content(/^.*\[abc123@41058 \] %msg%/)

    expect(runner).to render_file('/etc/rsyslog.d/10-loggly.conf').with_content(/^\$ModLoad imfile/)

    expect(runner).to render_file('/etc/rsyslog.d/10-loggly.conf').with_content(/^\$InputFileName \/var\/log\/somefile/)
    expect(runner).to render_file('/etc/rsyslog.d/10-loggly.conf').with_content(/^\$InputFileTag sometag\:/)
    expect(runner).to render_file('/etc/rsyslog.d/10-loggly.conf').with_content(/^\$InputFileStateFile somefile.state/)
  end

  it 'loads the imfile module when log_files is not empty' do
    runner = ChefSpec::Runner.new(CHEF_RUN_OPTIONS) do |node|
      node.set['loggly']['log_files'] =
      [ { filename: '/var/log/somefile', tag: 'sometag', statefile: 'somefile.state' } ]
    end.converge(described_recipe)

    expect(runner).to create_template('/etc/rsyslog.d/10-loggly.conf').with(
      variables: ({
        :tags => '',
        :monitor_files => true,
        :token => 'abc123'
      })
    )

    expect(runner).to render_file('/etc/rsyslog.d/10-loggly.conf').with_content(/^\$ModLoad imfile/)
    expect(runner).to render_file('/etc/rsyslog.d/10-loggly.conf').with_content(/^\$InputFilePollInterval 10/)
  end

end
