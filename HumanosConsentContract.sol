// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

//import 'openzeppelin-contracts/utils/math/Math.sol';

/**
 * @title ConsentContract
 * @dev ContractDescription
 * @custom:dev-run-script scripts/deploy_with_ethers.ts
 */
contract ConsentContract {
    struct ConsentTimestamps {
        uint256 startsAt;
        uint256 expiresAt;
    }

    /**
     * Address --> Hash --> ConsentTimestamps[]
     * Hash is a unique identifier for the consent, that stores what type of data is being shared and with whom is being shared
     * ConsentTimestamps is a struct that contains the start and end time of the consent
     * Hash is unique, to identify and to block repeated consents.
     *      Instead the user can only extend the consent if still active
     *      or start a new range of time for the consent to be valid
     */
    mapping(address => mapping(bytes32 => ConsentTimestamps[])) consents;

    event ConsentGiven(
        address indexed user,
        bytes32 indexed _hash,
        uint256 length,
        uint256 startsAt,
        uint32 hoursToExpire,
        uint256 expiresAt
    );

    event ChangeExpiresAt(
        address indexed user,
        bytes32 indexed _hash,
        uint256 length,
        uint256 newExpiresAt
    );

    event ModifyFutureConsent(
        address indexed user,
        bytes32 indexed _hash,
        uint256 length,
        uint256 newStartsAt,
        uint256 newExpiresAt
    );

    event EndFutureConsent(
        address indexed user,
        bytes32 indexed _hash,
        uint256 length
    );

    modifier validStartsAt(uint256 startsAt) {
        require(startsAt >= block.timestamp, 'Invalid startsAt');
        _;
    }

    modifier validActiveHours(uint32 hoursToExpire) {
        require(hoursToExpire >= 3, 'At least 3 hour active');
        _;
    }

    /**
     * Gives imeadiate consent
     * @param _hash The hash of the consent
     * @param hoursToExpire The number of active hours
     * @notice must be at least one hour active
     */
    function giveImeadiateConsent(
        bytes32 _hash,
        uint32 hoursToExpire
    ) external {
        giveConsent(_hash, block.timestamp, hoursToExpire);
    }

    /**
     * Ends future consents, or terminates active consents
     * @param _hash The hash of the consent
     */

    function endConsent(bytes32 _hash) external {
        uint256 length = consents[msg.sender][_hash].length;
        require(length > 0, 'No consent found');
        require(
            block.timestamp < consents[msg.sender][_hash][length - 1].expiresAt,
            'Already expired'
        );
        if (
            block.timestamp > consents[msg.sender][_hash][length - 1].startsAt
        ) {
            // Future consent - Delete
            consents[msg.sender][_hash].pop();
            emit EndFutureConsent(msg.sender, _hash, length);
        } else {
            // Active consent - Terminate
            consents[msg.sender][_hash][length - 1].expiresAt = block.timestamp;
            emit ChangeExpiresAt(msg.sender, _hash, length, block.timestamp);
        }
    }

    /**
     * Extends the consent
     * @param _hash The hash of the consent
     * @param hoursToExpire Extend by this number of hours
     * @notice hoursToExpire must be at least 1 more hour active
     * @notice Can only extend if the consent is still active
     */
    function extend(
        bytes32 _hash,
        uint32 hoursToExpire
    ) external validActiveHours(hoursToExpire) {
        uint256 length = consents[msg.sender][_hash].length;
        require(length > 0, 'No consent found');
        uint256 expiresAt = consents[msg.sender][_hash][length - 1].expiresAt;
        require(block.timestamp < expiresAt, 'Cant extend if already expired');
        uint256 newExpiresAt = expiresAt + hoursToExpire * 1 hours;
        consents[msg.sender][_hash][length - 1].expiresAt = newExpiresAt;
        emit ChangeExpiresAt(msg.sender, _hash, length, newExpiresAt);
    }

    /**
     * Sets a future consent to start now instead
     * @param _hash The hash of the consent
     */
    function modifyFutureConsentStartNow(
        bytes32 _hash,
        uint32 hoursToExpire
    ) external validActiveHours(hoursToExpire) {
        modifyFutureConsent(_hash, block.timestamp, hoursToExpire);
    }

    /**
     * Changes start time and duration of a future consent
     * @param _hash The hash of the consent
     */
    function modifyFutureConsent(
        bytes32 _hash,
        uint256 newStartsAt,
        uint32 hoursToExpire
    ) public validActiveHours(hoursToExpire) validStartsAt(newStartsAt) {
        uint256 length = consents[msg.sender][_hash].length;
        require(length > 0, 'No consent found');
        uint256 startsAt = consents[msg.sender][_hash][length - 1].startsAt;
        require(block.timestamp > startsAt, 'Not a future consent');
        consents[msg.sender][_hash][length - 1].startsAt = newStartsAt;
        consents[msg.sender][_hash][length - 1].expiresAt =
            newStartsAt +
            hoursToExpire *
            1 hours;
        emit ModifyFutureConsent(
            msg.sender,
            _hash,
            length,
            newStartsAt,
            newStartsAt + hoursToExpire * 1 hours
        );
    }

    /**
     * Initiates a new instance for this consent
     * @param _hash The hash of the consent
     * @param startsAt The time when the consent starts
     * @param hoursToExpire The number of active hours
     * @notice must be at least 3 hours active
     */
    function giveConsent(
        bytes32 _hash,
        uint256 startsAt,
        uint32 hoursToExpire
    ) public validActiveHours(hoursToExpire) validStartsAt(startsAt) {
        require(startsAt >= block.timestamp, 'Current time or future');
        uint256 length = consents[msg.sender][_hash].length;
        // Firt consent or Last consent is expired
        if (length > 0) {
            // Last consent is expired
            require(
                block.timestamp >
                    consents[msg.sender][_hash][length - 1].expiresAt,
                'Last instance of this consent must already be expired'
            );
        }
        uint256 expiresAt = startsAt + hoursToExpire * 1 hours;
        consents[msg.sender][_hash].push(
            ConsentTimestamps(startsAt, expiresAt)
        );
        emit ConsentGiven(
            msg.sender,
            _hash,
            length,
            startsAt,
            hoursToExpire,
            expiresAt
        );
    }

    /**
     * Checks the validity of multiple consents at specific timestamps.
     * This function determines whether each consent was valid at the given timestamp.
     *
     * @param owners The addresses of the owners of the consents.
     * @param _hashes The hashes representing each consent.
     * @param indexes The indexes indicating the specific consent instance for each owner-hash pair. It is used to identify which consent version is being checked.
     * @param timestamps The timestamps at which the validity of each consent needs to be verified.
     * @return bool[] An array of booleans indicating the validity of each consent at the specified timestamp.
     * @dev Used for integrity checks, access control mechanisms, and verification processes.
     */
    function consentsWereValid(
        address[] memory owners,
        bytes32[] memory _hashes,
        uint16[] memory indexes,
        uint256[] memory timestamps
    ) external view returns (bool[] memory) {
        require(
            _hashes.length == owners.length &&
                _hashes.length == timestamps.length,
            'Hashes array should have the same size as senders array'
        );
        bool[] memory validities = new bool[](_hashes.length);
        for (uint16 i = 0; i < _hashes.length; i++) {
            validities[i] = consentIsValid(owners[i], _hashes[i]);
            address owner = owners[i];
            bytes32 _hash = _hashes[i];
            uint16 index = indexes[i];
            uint256 timestamp = timestamps[i];
            uint256 length = consents[owner][_hash].length;
            if (
                length == 0 ||
                index >= length ||
                timestamp < consents[owner][_hash][index].startsAt ||
                block.timestamp > consents[owner][_hash][index].expiresAt
            ) validities[i] = false;
            else validities[i] = true;
        }
        return validities;
    }

    /**
     * Checks the validity of multiple consents at specific timestamps.
     * This function determines whether each consent was valid at the given timestamp.
     *
     * @param owners The addresses of the owners of the consents.
     * @param _hashes The hashes representing each consent.
     * @param indexes The indexes indicating the specific consent instance for each owner-hash pair. It is used to identify which consent version is being checked.
     * @param timestamps The timestamps at which the validity of each consent needs to be verified.
     * @return bool[] An array of booleans indicating the validity of each consent at the specified timestamp.
     * @dev Used for integrity checks, access control mechanisms, and verification processes.
     */

    /**
     * Get the start and end timestamp of multiple consents at specific instances
     * @param owners The addresses of the owners of the consents.
     * @param _hashes The hashes representing each consent.
     * @param indexes The indexes indicating the specific consent instance for each owner-hash pair. It is used to identify which consent version to fetch.
     * @return consentTimestamps The timestamps of the consent at specified instances
     * @dev Used for integrity checks, access control mechanisms, and verification processes.
     */
    function getMultipleConsentTimestamps(
        address[] memory owners,
        bytes32[] memory _hashes,
        uint16[] memory indexes
    ) external view returns (ConsentTimestamps[] memory) {
        require(
            owners.length == _hashes.length && _hashes.length == indexes.length,
            'Arrays must be of the same length'
        );
        require(owners.length > 1, 'Call getConsentTimestamps instead');

        ConsentTimestamps[]
            memory consentTimestampsArray = new ConsentTimestamps[](
                owners.length
            );

        for (uint i = 0; i < owners.length; i++) {
            // Call getConsentTimestamps for each set of parameters
            consentTimestampsArray[i] = getConsentInstanceTimestamps(
                owners[i],
                _hashes[i],
                indexes[i]
            );
        }
        return consentTimestampsArray;
    }

    /**
     * Get the start and end timestamp of all the instances of a consent
     * @param owner The addresses of the owner of the consent.
     * @param _hash The hash of the consent.
     * @return consentTimestamps The timestamps of the consent at each instance
     * @dev Used for integrity checks, access control mechanisms, and verification processes.
     */
    function getConsentAllInstancesTimestamps(
        address owner,
        bytes32 _hash
    ) external view returns (ConsentTimestamps[] memory) {
        uint256 length = consents[owner][_hash].length;
        require(length > 0, 'Consent not found');
        ConsentTimestamps[]
            memory consentTimestampsArray = new ConsentTimestamps[](length);
        for (uint16 i = 0; i < length; i++) {
            consentTimestampsArray[i] = getConsentInstanceTimestamps(
                owner,
                _hash,
                i
            );
        }
        return consentTimestampsArray;
    }

    /**
     * Checks if a consent is valid at the current time
     * @param owner The address of the owner of the consent
     * @param _hash The hash of the consent
     * @return true if the consent is valid, false otherwise
     * @dev Used by frontend, to avoid unnecessary write calls
     */
    function consentIsValid(
        address owner,
        bytes32 _hash
    ) public view returns (bool) {
        uint256 length = consents[owner][_hash].length;
        if (
            length == 0 ||
            block.timestamp < consents[owner][_hash][length - 1].startsAt ||
            block.timestamp > consents[owner][_hash][length - 1].expiresAt
        ) return false;
        else return true;
    }

    /**
     * Get the start and end timestamp for the last instance of a consent
     * @param owner The address of the owner of the consent
     * @param _hash The hash of the consent
     * @return consentTimestamps The timestamps of the consent for the last instance
     * @dev Used by frontend, to avoid unnecessary write calls
     */
    function getConsentLastInstanceTimestamps(
        address owner,
        bytes32 _hash
    ) external view returns (ConsentTimestamps memory consentTimestamps) {
        uint256 length = consents[owner][_hash].length;
        require(length > 0, 'No consent found');
        return consents[owner][_hash][length - 1];
    }

    /**
     * Get the start and end timestamp for a specific instance of a consent
     * @param owner The address of the owner of the consent
     * @param _hash The hash of the consent
     * @param index The instance of the consent.
     * @return consentTimestamps The timestamps of the consent for the specified instance
     * @dev Used for integrity checks, access control mechanisms, and verification processes.
     */
    function getConsentInstanceTimestamps(
        address owner,
        bytes32 _hash,
        uint16 index
    ) public view returns (ConsentTimestamps memory consentTimestamps) {
        uint256 length = consents[owner][_hash].length;
        require(length > 0, 'No consent found');
        require(index < length, 'Index out of bounds');
        return consents[owner][_hash][index];
    }
}
