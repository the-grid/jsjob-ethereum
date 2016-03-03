Web3 = require "web3"
Pudding = require "ether-pudding"
PuddingLoader = require "ether-pudding/loader"
Ipfs = require 'ipfs-api'

Runner = require './runner'

class Worker
  constructor: (@options = {}) ->
    @options.ethereum = {} unless @options.ethereum
    @options.ethereum.rpc = 'http://localhost:8545' unless @options.ethereum.rpc
    @options.ethereum.contractsDir = './environments/development/contracts' unless @options.ethereum.contractsDir
    @options.ipfs = {} unless @options.ipfs
    @options.ipfs.apiAddr = '/ip4/127.0.0.1/tcp/5001' unless @options.ipfs.apiAddr

    @agencyWatcher = null
    @preparePudding()
    @prepareIpfs()
    @seenJobIds = []
    @runner = new Runner @options.runner

  preparePudding: ->
    @web3 = new Web3()
    Pudding.setWeb3 @web3
    p = new Web3.providers.HttpProvider @options.ethereum.rpc
    @web3.setProvider p

  prepareIpfs: ->
    @ipfs = Ipfs @options.ipfs.apiAddr

  loadContracts: (callback) ->
    contracts = {}
    PuddingLoader.load @options.ethereum.contractsDir, Pudding, contracts, (err, names) ->
      return callback err if err
      return callback null, contracts

  subscribeAgency: (agency, callback) ->
    @agencyWatcher = agency.JobPosted()
    @agencyWatcher.watch (err, event) =>
      return callback err if err
      jobId = event.args.jobId.c[0]

      # Avoid duplicates. Due to multiple confirmations?
      # FIXME: Probably we should wait for a certain number before considering it legit
      if jobId in @seenJobIds
        console.log "Duplicate job #{jobId} received"
        return
      @seenJobIds.push jobId

      return callback null, jobId

  startRunner: (callback) ->
    @runner.start (err) ->
      return callback err if err
      do callback

  runJob: (job, callback) ->
    codeUrl = 'http://localhost:3000/test/fixtures/return-original.js'
    inputData = {
        'hello': 'world!'
    }
    jobOptions = {}
    console.time "Job #{job}"
    @runner.performJob codeUrl, inputData, jobOptions, (err, j) ->
      console.timeEnd "Job #{job}"
      return callback err if err
      callback j

  start: (callback) ->
    @startRunner (err) =>
      return callback err if err
      @loadContracts (err, contracts) =>
        console.log err, contracts
        return callback err if err
        agency = contracts.JobAgency.deployed()
        console.log 'JobAgency address:', agency.address
        @subscribeAgency agency, (err, jobId) =>
          @runJob jobId, (err, result) =>
            console.log err, result

  stop: (callback) ->
    @agencyWatcher.stopWatching() if @agencyWatcher
    @agencyWatcher = null
    @runner.stop callback

exports.main = main = () ->
  w = new Worker
  w.start (err) ->
    if err
      console.error err
      process.exit 1

main() if not module.parent
