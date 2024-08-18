pragma solidity ^0.5.0;

import "./ownable.sol";

contract Exchain is Ownable{
    /*****************************************************************/
    //GLOBALS
    /*****************************************************************/

    //Struct for DB
    struct DB {
            //payload
            string data;

            //id
            uint uid;
            string name;
            address owner;

            //timing
            uint lastUpdated;
            uint readyTime;

            //sync mechanisms
            bool lock;
            bool rlock;
            uint numReaders;
        }
    
    // Mappings
    mapping (address => uint) private ownerToDB;
    mapping (address => uint) private ownerToDBCount;
    mapping (uint    => uint) private uidToDB;

    uint private size;                   //number of stored databases

    //Note:Would be something much longer to prevent continuous writes Ex:12 hours
    uint private cooldownTime = 10 seconds;  //protective write cooldown time              

    //Array containing databases
    DB[] private dbs;

    // Constructor
    constructor() public {
        size = 0;
        //make first slot be the Zeroth index
        dbs.push(DB("EMPTY", 0, "ZERO INDEX", address(0), 0, 0, true, true, 0));
    }

    /*****************************************************************/
    //Sync
    /*****************************************************************/
    /*Inaccessible events*/
    event DatabaseIsLocked(string name, address owner, address attemptedLocker);
    event DatabaseIsUnlocked(string name, address owner, address attemptedUnlocker);
    event DatabaseIsRLocked(string name, address owner, address attemptedLocker);
    event DatabaseIsRUnlocked(string name, address owner, address attemptedUnlocker);

    /// notice require ownership a database (not specfically the one you are calling)
    modifier ownsDB() {
        require(ownerToDBCount[msg.sender] == 1, "Caller does not own a db");
        _;
    }

    /// notice require participation in Exchain (ownDB or head entity)
    modifier participant() {
        require(((ownerToDBCount[msg.sender] == 1) || (isOwner() == true)), "Caller is not a part of Exchain");
        _;
    }

    /// notice acquire the main lock of a database
    /// dev event will go off if the lock is already obtained
    /// param {DB} storage _db - reference to database in dbs array
    function _acquireDB(DB storage _db) private participant {
        if(_db.lock != true){
            _db.lock = true;
        }
        else{
            emit DatabaseIsLocked(_db.name, _db.owner, msg.sender);
            revert("Database is currently locked by another entity");
        }  
    }

    /// notice release the main lock of a database
    /// dev event will go off if the lock was not locked, but was attempted to be unlocked (always an error state)
    /// param {DB} storage _db - reference to database in dbs array
    function _releaseDB(DB storage _db) private participant {
        if(_db.lock == true){
            _db.lock = false;
        }
        else{
            emit DatabaseIsUnlocked(_db.name, _db.owner, msg.sender);
            revert("Database was not locked and was attempted to be unlocked");
        }
    }

    /// notice acquire the read lock of a database
    /// dev event will go off if the lock is already obtained
    /// param {DB} storage _db - reference to database in dbs array
    function _acquireDB_r(DB storage _db) private participant {
        if(_db.rlock != true){
            _db.rlock = true;
        }
        else{
            emit DatabaseIsRLocked(_db.name, _db.owner, msg.sender);
            revert("Database is currently read locked by another reader");
        }  
        
    }

    /// notice release the read lock of a database
    /// dev event will go off if the read lock was not locked, but was attempted to be unlocked (always an error state)
    /// param {DB} storage _db - reference to database in dbs array
    function _releaseDB_r(DB storage _db) private participant {
        if(_db.rlock == true){
            _db.rlock = false;
        }
        else{
            emit DatabaseIsRUnlocked(_db.name, _db.owner, msg.sender);
            revert("Database was not read locked and was attempted to be read unlocked");
        }
    }

    /*****************************************************************/
    //Factory
    /*****************************************************************/

    /*Database added event*/
    event NewDatabaseCreated(uint index, string name, uint uid, address owner);
    event DatabaseDeleted(uint index, string name, uint uid, address owner);

    /*Error in repacking a empty slot in DBS event*/
    event ErrorFailureToPackEmptySlot(uint index, string name, address owner);

    //Support
    /*******************************************************************************************************/
    
    /// notice find first available slot in dbs array for a newly create database
    /// dev support to _addToDBS
    /// return returns- uint: index of available slot (zero if none across dbs length are avail)
    function _findAvailSlot() private view returns(uint){
        //index starts at 1
        for(uint i = 1; i < dbs.length; i++){
            //check to make sure the uid is 0 and string is empty
            //(impossible for this to occur unless deletion has happened bc uid is the string hashed)
            bytes memory emptyStringTest = bytes(dbs[i].name);
            if(dbs[i].uid == 0 && emptyStringTest.length == 0){
                return i;
            }
        }
        return 0;
    } 

    /// notice add a newly created database to the dbs array in an open slot of the existing length or append
    /// dev support to _createDB
    /// param {uint} uint _uid - generated unique ID for database
    /// param {string} memory _name - provided name of database
    /// param {address} _setOwner - address of who will own the database
    /// return {uint}- index of available slot (zero if none across dbs length are avail)
    function _addToDBS(uint _uid, string memory _name, address _setOwner) private returns(uint){
        //Check if there are open slots
        uint _index = 0;
        if(size < (dbs.length - 1)){
            //if there are find the first available slot that is available
            _index = _findAvailSlot();
            require(_index != 0);
        }

        //if is done so cooldown timing can be slightly more accurate, can restruct in future if wanting to save cond. checking
        uint32 _timeNow = uint32(now);
        uint32 _timeLtr = uint32(_timeNow + cooldownTime);
        if(_index == 0){
            //push returns length of array pushing to, -1 bc of zeroth index
            _index = dbs.push(DB("EMPTY", _uid, _name, _setOwner, _timeNow, _timeLtr, false, false, 0)) - 1;
        }
        else{
            dbs[_index] = DB("EMPTY", _uid, _name, _setOwner, _timeNow, _timeLtr, false, false, 0);
        }

        return _index;
    }

    /// notice create a database and add it to the dbs array
    /// dev support createDB
    /// param {uint} _uid - generated unique ID for database
    /// param {string} memory _name - provided name of database
    /// param {address} _setOwner - address of who will own the database
    function _createDB(uint _uid, string memory _name, address _setOwner) private{
        uint _index = _addToDBS(_uid, _name, _setOwner);

        ownerToDB[_setOwner] = _index;      //map owner to this dbs index
        ownerToDBCount[_setOwner] = 1;        //owner now owns 1 database
        uidToDB[_uid] = _index;             //link uib as alias to index

        size++;

        emit NewDatabaseCreated(_index, _name, _uid, _setOwner);
    }

    /// notice generate unique id for database by hashing provided database name
    /// dev provide _createDB w/ uid to support createDB
    /// param {string} memory _dbName - name of database
    /// return {uint} - 256-bit uid
    function _generateUniqueID(string memory _dbName) private pure returns (uint) {
        uint rand = uint(keccak256(abi.encodePacked(_dbName)));
        return rand;
    }

    /// notice check if the name is already used as a database name. No duplicate names bc of hashing to make uid.
    /// dev support createDB
    /// param {string} memory _name - intended name of database
    /// return {bool} - is the name already in use
    function _isNameInUse(string memory _name) private view returns (bool){
        uint _i = 0;
        for(_i = 1; _i < dbs.length; _i++){
            if( keccak256(abi.encodePacked((dbs[_i].name))) == keccak256(abi.encodePacked((_name))) ){
                return true;
            }
        }
        return false;
    }

    //Main Interface
    /*******************************************************************************************************/

    /// notice create a slot for a database
    /// dev only head entity that deploys smart contract can execute. Note: head entity may create their own database.
    /// param {string} memory _name - intended name of database
    /// param {address} _setOwner- intended owner of the database
    /// return {uint}- uid of database
    function createDB(string memory _name, address _setOwner) public onlyOwner returns (uint){
        require(ownerToDBCount[_setOwner] == 0, "Address cannot own more than one database");
        require(_setOwner != msg.sender, "The head entity may not create its own a database");
        require(_setOwner != address(0), "Address 0 cannot own a database");
        require(_isNameInUse(_name) == false, "No duplicate names across databases");

        uint _uid = _generateUniqueID(_name);
        _createDB(_uid, _name, _setOwner);
        
        return _uid;
    }

    /// notice delete an existing database
    /// dev only head entity that deploys smart contract can execute. Note: head entity may delete their own database.
    /// param {uint} _uid - unique 265-bit ID of database to be deleted
    function deleteDB(uint _uid) public onlyOwner {
        uint _index = uidToDB[_uid];

        DB storage _db = dbs[_index];
        require(_db.owner != msg.sender, "The head entity may not delete its own a database");

        //it is possible that the head entity can be denied from deleting by a current writer or current readers
        _acquireDB(_db);
        ownerToDBCount[_db.owner] = 0;
        ownerToDB[_db.owner] = 0;
        uidToDB[_db.uid] = 0;
        size--;
        emit DatabaseDeleted(_index, _db.name, _db.uid, _db.owner);
        delete dbs[_index];
    }

    /*****************************************************************/
    //Read/Write
    /*****************************************************************/

    /*State change events*/
    event DatabaseRead(string name, address owner, address reader, string data);
    event DatabaseUpdated(uint index, string name, uint nextTimeToUpdate, string newData);

    /*Cooldown events*/
    event DatabaseInCooldown(uint index, string name, uint nextTimeToUpdate);

    //Support
    /*******************************************************************************************************/

    /// notice check if cooldown is complete
    /// param {DB} storage _db - reference to database in dbs array
    /// return {bool} - has cooldown expired
    function _isReady(DB storage _db) private view returns (bool){
        return (_db.readyTime <= now);
    }

    /// notice prevent continuous writes by not allowing writing during a cooldown time
    /// param {DB} storage _db- reference to database in dbs array
    function _triggerCooldown(DB storage _db) private ownsDB {
       _db.readyTime = uint32(_db.lastUpdated + cooldownTime);
    }

    //Main Interface
    /*******************************************************************************************************/
    //Reader/Writers Problem if execution occurs concurrently on shards

    /// notice modify an owned database
    /// dev uses sync
    /// param {string} memory _data - string of data attempting to add
    function writeDB(string memory _data) public ownsDB{
       uint _index = ownerToDB[msg.sender];     //get index of database the you own

       DB storage _db = dbs[_index];

       bool _ready = _isReady(_db);
       if(_ready == false){
           emit DatabaseInCooldown(_index,_db.name,_db.readyTime);
       }

       require(_ready == true);
       _acquireDB(_db);

       _db.data = _data;
       _db.lastUpdated = now;       
       
       _triggerCooldown(_db);
       _releaseDB(_db);

       emit DatabaseUpdated(_index, _db.name, _db.readyTime, _db.data);
    }

    /// notice read an existing database contents
    /// dev uses sync
    /// param {uint} _uid - unique 265-bit ID you want to read
    /// return {string} memory - Database's contents
    function readDB(uint _uid) public participant returns (string memory) {
        uint _index = uidToDB[_uid];

        DB storage _db = dbs[_index];

        _acquireDB_r(_db);
        if(_db.numReaders == 0){
            _acquireDB(_db);
        }
        _db.numReaders++;
        _releaseDB_r(_db);

        string memory data = _db.data;

        _acquireDB_r(_db);
        _db.numReaders--;
        if(_db.numReaders == 0){
            _releaseDB(_db);
        }
        _releaseDB_r(_db);

        emit DatabaseRead(_db.name, _db.owner, msg.sender, data);

        return (data);
    }
}

//designed and coded by Steven Rosenthal