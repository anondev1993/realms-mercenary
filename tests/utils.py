
def pack_bounty_info(amount, deadline, is_lords, resource_id):
    offset=0
    #print(offset)
    # max resource id = 131 071
    packed_resource_id = (2**offset * resource_id)
    resource_id_nb_bits = 17
    # 17
    offset += resource_id_nb_bits
    # print(offset)

    # is lords is either 0 or 1
    packed_is_lords = (2**offset * is_lords)
    is_lords_nb_bits = 1
    # 18
    offset += is_lords_nb_bits
    # print(offset)

    # deadline max 268 435 455 blocks in the future assuming 1 second/block = 8.5 years
    packed_deadline = (2**offset * deadline)
    deadline_nb_bits = 28
    # 46
    offset+=deadline_nb_bits
    # print(offset)

    # amount max 206 bits = 102844034832575377634685573909834406561420991602098741459288063
    amount_nb_bits = 206
    packed_amount = (2**offset * amount)
    # 252
    offset+=amount_nb_bits
    # print(offset)

    return packed_resource_id + packed_is_lords + packed_deadline + packed_amount



def unpack_bounty_info(packed_bounty):
    # 0 
    index = 0
    mask_size = 2**17 - 1
    # 131071
    mask = 2**index * mask_size
    # print(index)
    # print(mask)
    resource_id = (packed_bounty & mask)//2**index

    # 17
    index += 17
    mask_size = 2**1 - 1
    # 131072
    mask = 2**index * mask_size
    # print(index)
    #print(mask)
    is_lords = (packed_bounty & mask)//2**index

    # 18
    index += 1
    mask_size = 2**28 - 1
    # 70368743915520
    mask = 2**index * mask_size
    # print(index)
    #print(mask)
    deadline = (packed_bounty & mask)//2**index

    # 46
    index += 28
    mask_size = 2**206 - 1
    # 7237005577332262213973186563042994240829374041602535252466098930125826424832
    mask = 2**index * mask_size
    # print(index)
    #print(mask)
    amount = (packed_bounty & mask)//2**index

    return resource_id, is_lords, deadline, amount

if __name__ == "__main__":
    # quick test to make sure it works
    # 102844034832575377634685573909834406561420991602098741459288063 is biggest amount possible for one bounty
    packed_data = pack_bounty_info(amount=102844034832575377634685573909834406561420991602098741459288063, deadline=1329, is_lords=1, resource_id=10334)
    resource_id, is_lords, deadline, amount = unpack_bounty_info(packed_data)
    assert resource_id == 10334
    assert is_lords == 1
    assert deadline == 1329
    assert amount == 102844034832575377634685573909834406561420991602098741459288063